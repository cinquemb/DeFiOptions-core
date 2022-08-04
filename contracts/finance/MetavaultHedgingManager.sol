pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/external/metavault/IPositionManager.sol";
import "../interfaces/external/metavault/IReader.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../utils/Convert.sol";

contract MetavaultHedgingManager is BaseHedgingManager {
    address public positionManagerAddr;
    address public readerAddr;
    uint private maxLeverage = 30;
    uint private minLeverage = 1;
    uint private defaultLeverage = 15;

    bytes32 private referralCode;

    // TODO: need to use constructor to initalizae
    function initialize(Deployer deployer, address _positionManager, address _reader, bytes32 _referralCode) internal {
        super.initialize(deployer);
        positionManagerAddr = _positionManager;
        readerAddr = _reader;
        referralCode = _referralCode;
    }

    function getPosSize(address underlying, address account, bool isLong) override public view returns (uint[] memory) {
        address[] memory allowedTokens = settings.getAllowedTokens();
        address[] memory _collateralTokens = new address[](allowedTokens.length);
        address[] memory _indexTokens = new address[](allowedTokens.length);
        bool[] memory _isLong = new bool[](allowedTokens.length);

        for (uint i=0; i<allowedTokens.length; i++) {
            _collateralTokens[i] = allowedTokens[i];
            _indexTokens[i] = underlying;
            _isLong[i] = isLong;
        }

        uint256[] memory posData = IReader(readerAddr).getPositions(
            IPositionManager(positionManagerAddr).vault(),
            account,
            _collateralTokens, //need to be the approved stablecoins on dod * [long, short]
            _indexTokens,
            _isLong
        );

        uint[] memory posSize = new uint[](allowedTokens.length);

        for (uint i=0; i<(allowedTokens.length); i++) {
            posSize[i] = posData[i*9];
        }

        return posSize;
    }

    function getHedgeExposure(address underlying, address account) override public view returns (int256) {
        address[] memory allowedTokens = settings.getAllowedTokens();
        address[] memory _collateralTokens = new address[](allowedTokens.length * 2);
        address[] memory _indexTokens = new address[](allowedTokens.length * 2);
        bool[] memory _isLong = new bool[](allowedTokens.length * 2);

        for (uint i=0; i<allowedTokens.length; i++) {
            
            _collateralTokens[i] = allowedTokens[i];
            _collateralTokens[i] = allowedTokens[i];
            
            _indexTokens[i] = underlying;
            _indexTokens[i] = underlying;
            
            _isLong[i] = true;
            _isLong[i] = false;
        }

        uint256[] memory posData = IReader(readerAddr).getPositions(
            IPositionManager(positionManagerAddr).vault(),
            account,
            _collateralTokens, //need to be the approved stablecoins on dod * [long, short]
            _indexTokens,
            _isLong
        );

        //https://docs.metavault.trade/contracts#positions-list

        int256 totalExposure = 0;
        for (uint i=0; i<(allowedTokens.length*2); i++) {
            if (posData[(i*9)] != 0) {
                if (_isLong[i] == true) {
                    totalExposure = totalExposure.add(int256(posData[(i*9)]));
                } else {
                    totalExposure = totalExposure.sub(int256(posData[(i*9)]));
                }
            }
        }

        return Convert.formatValue(totalExposure, 18, 30);
    }
    

    function idealHedgeExposure(address underlying, address account) override public view returns (int256) {
        // look at order book for account and compute the delta for the given underlying (depening on net positioning of the options outstanding and the side of the trade the account is on)
        (,address[] memory _tokens, uint[] memory _holding,, uint[] memory _uncovered,) = exchange.getBook(account);

        int totalDelta = 0;
        for (uint i = 0; i < _tokens.length; i++) {
            address _tk = _tokens[i];
            IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);
            if (UnderlyingFeed(opt.udlFeed).getUnderlyingAddr() == underlying){
                int256 delta;

                if (_uncovered[i].sub(_holding[i]) > 0) {
                    // net short this option, thus mult by -1
                    delta = ICollateralManager(
                        settings.getUdlCollateralManager(opt.udlFeed)
                    ).calcDelta(
                        opt,
                        _uncovered[i].sub(_holding[i])
                    ).mul(-1);
                } else {
                    // net long thus does not need to be modified
                    delta = ICollateralManager(
                        settings.getUdlCollateralManager(opt.udlFeed)
                    ).calcDelta(
                        opt,
                        _holding[i]
                    );
                }

                totalDelta = totalDelta.add(delta);
            }
        }
        return totalDelta;
    }
    
    function realHedgeExposure(address udlFeedAddr, address account) override public view returns (int256) {
        // look at metavault exposure for underlying, and divide by asset price
        (, int256 udlPrice) = UnderlyingFeed(udlFeedAddr).getLatestPrice();
        int256 exposure = getHedgeExposure(UnderlyingFeed(udlFeedAddr).getUnderlyingAddr(), account);
        return exposure.div(udlPrice);
    }
    
    function balanceExposure(address udlFeedAddr, address account) override external returns (bool) {

        address underlying = UnderlyingFeed(udlFeedAddr).getUnderlyingAddr();
        int256 ideal = idealHedgeExposure(underlying, account);
        int256 real = realHedgeExposure(underlying, account);
        int256 diff = ideal - real;
        address[] memory allowedTokens = settings.getAllowedTokens();
        uint totalStables = creditProvider.totalTokenStock();

        uint poolLeverage = (settings.isAllowedCustomPoolLeverage(account) == true) ? IGovernableLiquidityPool(account).getLeverage() : defaultLeverage;


        require(poolLeverage <= maxLeverage && poolLeverage >= minLeverage, "leverage out of range");

        (, int256 udlPrice) = UnderlyingFeed(udlFeedAddr).getLatestPrice();

        if (ideal >= 0) {
            uint256 pos_size = uint256(MoreMath.abs(diff));
            if (real > 0) {
                //need to close long position first
                uint[] memory openPos = getPosSize(underlying, account, true);

                //need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)
                for(uint i=0; i< openPos.length; i++){
                    (uint r, uint b) = settings.getTokenRate(allowedTokens[i]);
                    IERC20 t = IERC20(allowedTokens[i]);
                    uint balBefore = t.balanceOf(address(creditProvider));
                    address[] memory _path = new address[](2);
                    _path[0] = underlying;
                    _path[1] = allowedTokens[i];

                    IPositionManager(positionManagerAddr).decreasePositionAndSwap(
                        _path, //address[] memory _path
                        underlying,//address _indexToken,
                        openPos[i],//uint256 _collateralDelta, USD 1e30 mult
                        openPos[i],//uint256 _sizeDelta, USD 1e30 mult
                        true,//bool _isLong,
                        address(creditProvider),//address _receiver,
                        uint256(Convert.formatValue(uint256(udlPrice).add(uint256(udlPrice).mul(5).div(1000)), 30, 18)), //uint256 _price, use current price of underlying, 5/1000 slippage? is this needed?, USD 1e30 mult
                        uint256(Convert.formatValue(openPos[i], 18, 30)),//uint256 _minOut, TOKEN DECIMALS
                        referralCode//bytes32 _referralCode
                    );
                    uint balafter = t.balanceOf(address(creditProvider));
                    uint diffBal = balafter.sub(balBefore);
                    //back to exchange decimals
                    creditProvider.creditPoolBalance(account, allowedTokens[i], diffBal);    
                }
                
                pos_size = uint256(ideal);
            }
            
            // increase short position by pos_size
            if (pos_size != 0) {
                //TODO: need to add function to exchange to transfer stablecoinds to hedging contract, then from hedging contract to metavault
                uint totalPosValue = pos_size.mul(uint256(udlPrice));
                uint totalPosValueToTransfer = totalPosValue.div(poolLeverage);

                // hedging should fail if not enough stables in exchange
                if (totalStables.mul(poolLeverage) > totalPosValue) {
                    for (uint i=0; i< allowedTokens.length; i++) {

                        if (totalPosValueToTransfer > 0) {
                            IERC20 t = IERC20(allowedTokens[i]);
                            address routerAddr = IPositionManager(positionManagerAddr).router();
                            
                            (uint r, uint b) = settings.getTokenRate(allowedTokens[i]);

                            uint bal = t.balanceOf(address(creditProvider)).mul(b).div(r); //convert to exchange decimals
                            if (b != 0) {
                                uint v = MoreMath.min(totalPosValueToTransfer, bal);
                                if (t.allowance(address(this), address(routerAddr)) > 0) {
                                    t.safeApprove(address(routerAddr), 0);
                                }
                                t.safeApprove(address(routerAddr), v.mul(r).div(b));

                                //transfer collateral from credit provider to hedging manager and debit pool bal
                                address[] memory at = new address[](1);
                                at[0] = allowedTokens[i];

                                uint[] memory tv = new uint[](1);
                                tv[0] = v;


                                ICollateralManager(
                                    settings.getUdlCollateralManager(
                                        udlFeedAddr
                                    )
                                ).borrowTokensByPreference(
                                    address(this), v, at, tv
                                );

                                v = v.mul(r).div(b);//converts to token decimals

                                IPositionManager(positionManagerAddr).increasePosition(
                                    at,//address[] memory _path,
                                    underlying,//address _indexToken,
                                    v,//uint256 _amountIn, TOKEN DECIMALS
                                    0,//uint256 _minOut, //_minOut can be zero if no swap is required , TOKEN DECIMALS
                                    uint256(Convert.formatValue(v.mul(poolLeverage).mul(r).div(b), 30, 18)),//uint256 _sizeDelta, USD 1e30 mult
                                    false,// bool _isLong
                                    uint256(Convert.formatValue(uint256(udlPrice).add(uint256(udlPrice).mul(5).div(1000)), 30, 18)),//uint256 _price, USD 1e30 mult
                                    referralCode//bytes32 _referralCode
                                );

                                //back to exchange decimals
                                totalPosValueToTransfer = totalPosValueToTransfer.sub(v.mul(r).div(b));
                            }                            
                        }
                    }
                }
            }
        } else if (ideal < 0) {
            uint256 pos_size = uint256(MoreMath.abs(diff));
            if (real < 0) {
                // need to close short position first
                // need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)
                
                uint[] memory openPos = getPosSize(underlying, account, true);
                
                for(uint i=0; i< openPos.length; i++){

                    (uint r, uint b) = settings.getTokenRate(allowedTokens[i]);
                    IERC20 t = IERC20(allowedTokens[i]);
                    uint balBefore = t.balanceOf(address(creditProvider));

                    IPositionManager(positionManagerAddr).decreasePosition(
                        allowedTokens[i],//address _collateralToken,
                        underlying,//address _indexToken,
                        openPos[i],//uint256 _collateralDelta,
                        openPos[i],//uint256 _sizeDelta,
                        false,//bool _isLong,
                        address(creditProvider),//address _receiver,
                        Convert.formatValue(uint256(udlPrice).sub(uint256(udlPrice).mul(5).div(1000)), 30, 18),//uint256 _price,
                        referralCode//bytes32 _referralCode
                    );
                    uint balAfter = t.balanceOf(address(creditProvider));
                    uint diffBal = balAfter.sub(balBefore);
                    creditProvider.creditPoolBalance(account, allowedTokens[i], diffBal);
                }

                pos_size = uint256(MoreMath.abs(ideal));
            }

            // increase long position by pos_size
            if (pos_size != 0) {

                //TODO: need to add function to exchange to transfer stablecoinds to hedging contract, then from hedging contract to metavault
                uint totalPosValue = pos_size.mul(uint256(udlPrice));
                uint totalPosValueToTransfer = totalPosValue.div(poolLeverage);

                // hedging should fail if not enough stables in exchange
                if (totalStables.mul(poolLeverage) > totalPosValue) {
                    for (uint i=0; i< allowedTokens.length; i++) {

                        if (totalPosValueToTransfer > 0) {
                            IERC20 t = IERC20(allowedTokens[i]);
                            address routerAddr = IPositionManager(positionManagerAddr).router();
                            
                            (uint r, uint b) = settings.getTokenRate(allowedTokens[i]);
                            uint bal = t.balanceOf(address(creditProvider)).mul(b).div(r);
                            if (b != 0) {
                                uint v = MoreMath.min(totalPosValueToTransfer, bal);
                                if (t.allowance(address(this), address(routerAddr)) > 0) {
                                    t.safeApprove(address(routerAddr), 0);
                                }
                                t.safeApprove(address(routerAddr), v.mul(r).div(b));

                                //transfer collateral from credit provider to hedging manager and debit pool bal
                                address[] memory at = new address[](1);
                                address[] memory at_s = new address[](2);
                                at[0] = allowedTokens[i];
                                
                                at_s[0] = allowedTokens[i];
                                at_s[1] = underlying;

                                uint[] memory tv = new uint[](1);
                                tv[0] = v;

                                ICollateralManager(
                                    settings.getUdlCollateralManager(
                                        udlFeedAddr
                                    )
                                ).borrowTokensByPreference(
                                    address(this), v, at, tv
                                );

                                v = v.mul(r).div(b);//converts to token decimals

                                IPositionManager(positionManagerAddr).increasePosition(
                                    at_s,//address[] memory _path,
                                    underlying,//address _indexToken,
                                    v,//uint256 _amountIn, TOKEN DECIMALS
                                    Convert.formatValue(v.div(uint256(udlPrice)).mul(b).div(r), 30, 18),//uint256 _minOut, //_minOut can be zero if no swap is required , TOKEN DECIMALS
                                    Convert.formatValue(v.mul(poolLeverage).mul(b).div(r), 30, 18),//uint256 _sizeDelta, USD 1e30 mult
                                    true,// bool _isLong
                                    Convert.formatValue(uint256(udlPrice).add(uint256(udlPrice)).mul(5).div(1000), 30, 18),//uint256 _price, USD 1e30 mult
                                    referralCode//bytes32 _referralCode
                                );

                                //back to exchange decimals
                                totalPosValueToTransfer = totalPosValueToTransfer.sub(v.mul(r).div(b));
                            }                             
                        }
                    }
                }
            }
        }
    } 
}