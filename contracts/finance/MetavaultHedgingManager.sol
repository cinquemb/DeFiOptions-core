pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/external/metavault/IPositionManager.sol";
import "../interfaces/external/metavault/IReader.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/UnderlyingFeed.sol";

contract MetavaultHedgingManager is BaseHedgingManager {
    address public positionManagerAddr;
    address public readerAddr;
    uint private maxLeverage = 30;
    uint private minLeverage = 1;
    uint private defaultLeverage = 15;

    bytes32 private referralCode;

    // TODO: need to use constructor to initalizae
    function initialize(Deployer deployer, address _positionManager, address _reader, address _referralCode) override internal {
        super.initialize(deployer);
        positionManagerAddr = _positionManager;
        readerAddr = _reader;
        referralCode = referralCode;
    }

    function getPosSize(address underlying, address account, bool isLong) override public view returns (uint[] memory) {
        address[] memory allowedTokens = settings.getAllowedTokens();
        address[] memory _collateralTokens = new address[](allowedTokens.length);
        address[] memory _indexTokens = new address[](allowedTokens.length);
        bool[] memory _isLong = new bool[](allowedTokens.length);

        for (uint i=0; i<allowedTokens.length; i++) {
            _collateralTokens.push(allowedTokens[i]);
            _indexTokens.push(underlying);
            _isLong.push(isLong);
        }

        uint256[] memory posData = IReader(reader).getPositions(
            IPositionManager(positionManagerAddr).vault(),
            account,
            _collateralTokens, //need to be the approved stablecoins on dod * [long, short]
            _indexTokens,
            isLong
        );

        uint[] memory posSize = new address[](allowedTokens.length);

        for (uint i=0; i<(allowedTokens.length); i++) {
            posSize.push(posData[i*9]);
        }

        return posSize;
    }

    function getHedgeExposure(address underlying, address account) override public view returns (int) {
        address[] memory allowedTokens = settings.getAllowedTokens();
        address[] memory _collateralTokens = new address[](allowedTokens.length * 2);
        address[] memory _indexTokens = new address[](allowedTokens.length * 2);
        bool[] memory _isLong = new bool[](allowedTokens.length * 2);

        for (uint i=0; i<allowedTokens.length; i++) {
            
            _collateralTokens.push(allowedTokens[i]);
            _collateralTokens.push(allowedTokens[i]);
            
            _indexTokens.push(underlying);
            _indexTokens.push(underlying);
            
            _isLong.push(true);
            _isLong.push(false);
        }

        uint256[] memory posData = IReader(reader).getPositions(
            IPositionManager(positionManagerAddr).vault(),
            account,
            _collateralTokens, //need to be the approved stablecoins on dod * [long, short]
            _indexTokens,
            _isLong
        );

        /*
            posData[i * POSITION_PROPS_LENGTH] = size;
            posData[i * POSITION_PROPS_LENGTH + 1] = collateral;
            posData[i * POSITION_PROPS_LENGTH + 2] = averagePrice;
            posData[i * POSITION_PROPS_LENGTH + 3] = entryFundingRate;
            posData[i * POSITION_PROPS_LENGTH + 4] = hasRealisedProfit ? 1 : 0;
            posData[i * POSITION_PROPS_LENGTH + 5] = realisedPnl;
            posData[i * POSITION_PROPS_LENGTH + 6] = lastIncreasedTime;
            posData[i * POSITION_PROPS_LENGTH + 7] = hasProfit ? 1 : 0;
            posData[i * POSITION_PROPS_LENGTH + 8] = delta;
        /*

        int256 totalExposure = 0;
        for (uint i=0; i<(allowedTokens.length*2); i++) {
            if (posData[(i*9)] != 0) {
                if (_isLong[i] == true) {
                    totalExposure = totalExposure.add(posData[(i*9)])
                } else {
                    totalExposure = totalExposure.sub(posData[(i*9)])
                }
            }
        }

        return totalExposure;
    }
    

    function idealHedgeExposure(address underlying, address account) override public view returns (int256) {
        // look at order book for account and compute the delta for the given underlying (depening on net positioning of the options outstanding and the side of the trade the account is on)
        (,address[] memory _tokens, uint[] memory _holding,, uint[] memory _uncovered,) = exchange.getBook(account);

        int totalDelta = 0;
        for (uint i = 0; i < _tokens.length; i++) {
            address _tk = _tokens[i];
            IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);
            if (exchange.getUnderlyingAddr(opt) == underlying){
                int256 delta;

                if (_uncovered[i].sub(_holding[i]) > 0) {
                    // net short this option, thus mult by -1
                    delta = ICollateralManager(
                        settings.getUdlCollateralManager(opt.udlFeed)
                    ).calcDelta(
                        opt,
                        _uncovered[i].sub(_holding[i]),
                    ).mul(-1);
                } else {
                    // net long thus does not need to be modified
                    delta = ICollateralManager(
                        settings.getUdlCollateralManager(opt.udlFeed)
                    ).calcDelta(
                        opt,
                        _holding[i],
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
        //options trades should trigger this

            /*
                USD values for _sizeDelta and _price are multiplied by (10 ** 30), so for example to open a long position of size 1000 USD, the value 1000 * (10 ** 30) should be used 

                need to convert from 10 ** 18 and back when appropriate

                //how to deal with buying againt someone who is providing covered call collateral in the exchange (pool will be long calls and needs to short)?
                    - first check for avaialble stable coins (this needs to be done by default for both long/short)
                        - located at the credit provider addr
                        - credit provider addr needs to approve proper metvault addr

                    -if no stablecoins, then use avaiable underlying asset? or only allow stablecoin covered volume for pools?
                        - located at the vault addr
                        - vault addr needs to approve the prover metavault addr
                            - no swap required for longs

                - _path allows swapping to the collateralToken if needed 
                - For longs, the collateralToken must be the same as the indexToken 
                - For shorts, the collateralToken can be any stablecoin token 
                - _minOut can be zero if no swap is required 

                //GET FEEDBACK ON LEVERAGE
            */

        address underlying = UnderlyingFeed(udlFeedAddr).getUnderlyingAddr();
        int256 ideal = idealHedgeExposure(underlying, account);
        int256 real = realHedgeExposure(underlying, account);
        int256 diff = ideal - real;
        address[] memory allowedTokens = settings.getAllowedTokens();
        uint totalStables = creditProvider.totalTokenStock();

        uint poolLeverage = (settings.isAllowedCustomPoolLeverage(account) == true) ? IGovernableLiquidityPool(account).getLeverage() : defaultLeverage;


        requre(poolLeverage <= maxLeverage && poolLeverage >= minLeverage, "leverage out of range");

        /*
            - FOR increasePosition
            - _sizeDelta is 0 for adding collateral with non zero _amountIn
            - pool needs to have permision to sends funds from their exchange balance to perp protocol
        */

        /*
            FOR decreasePositionAndSwap
            - set _collateralDelta to the amount the exchagne wants to withdraw from perp protocol
            - _receiver address needs to be withdrawn to the credit provider address in the acceabtle stablecoins
                - liquidty pool needs to be credited with the amount recieved
        */

        (, int256 udlPrice) = UnderlyingFeed(udlFeedAddr).getLatestPrice();

        if (ideal >= 0) {
            uint256 pos_size = uint256(abs(diff));
            if (real > 0) {
                //need to close long position first
                uint[] memory openPos = getPosSize(underlying, account, true);

                //need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)
                for(uint i=0; i< openPos.length; i++){
                    (uint r, uint b) = settings.getTokenRate(allowedTokens[i]);
                    IERC20 t = IERC20(allowedTokens[i]);
                    uint balBefore = t.balanceOf(address(creditProvider)).mul(b).div(r);
                    IPositionManager(positionManagerAddr).decreasePositionAndSwap(
                        [underlying, allowedTokens[i]], //address[] memory _path
                        underlying,//address _indexToken,
                        openPos[i],//uint256 _collateralDelta,
                        openPos[i],//uint256 _sizeDelta,
                        true,//bool _isLong,
                        address(creditProvider),//address _receiver,
                        uint256(udlPrice).sub(uint256(udlPrice).mul(5).div(1000)), //use current price of underlying, 5/1000 slippage? is this needed?
                        openPos[i],//uint256 _minOut
                        _referralCode//bytes32 _referralCode
                    );
                    uint balafter = t.balanceOf(address(creditProvider)).mul(b).div(r);
                    uint diffBal = balafter.sub(balBefore);
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

                        /*
                            TODO: transfer login needs to be changed to factor in contract perms for transfering from credit provider
                        */

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
                                t.safeApprove(address(routerAddr), v);

                                //transfer collateral from credit provider to hedging manager and debit pool bal
                                ICollateralManager(
                                    settings.getUdlCollateralManager(
                                        udlFeedAddr
                                    )
                                ).borrowTokensByPreference(
                                    address(this), v, [allowedTokens[i]], [v]
                                )
                            }

                            IPositionManager(positionManagerAddr).increasePosition(
                                [allowedTokens[i]],//address[] memory _path,
                                underlying,//address _indexToken,
                                v,//uint256 _amountIn,
                                0,//uint256 _minOut, //_minOut can be zero if no swap is required 
                                v.mul(poolLeverage),//uint256 _sizeDelta,
                                false,// bool _isLong
                                uint256(udlPrice).sub(uint256(udlPrice).mul(5).div(1000)),//uint256 _price,
                                referralCode//bytes32 _referralCode
                            );

                            totalPosValueToTransfer = totalPosValueToTransfer.sub(v);
                        }
                    }
                }
            }
        } else if (ideal < 0) {
            uint256 pos_size = uint256(abs(diff));
            if (real < 0) {
                // need to close short position first
                //need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)
                for(uint i=0; i< openPos.length; i++){

                    (uint r, uint b) = settings.getTokenRate(allowedTokens[i]);
                    IERC20 t = IERC20(allowedTokens[i]);
                    uint balBefore = t.balanceOf(address(creditProvider)).mul(b).div(r);
                    IPositionManager(positionManagerAddr).decreasePositionAndSwap(
                        [underlying, allowedTokens[i]], //address[] memory _path
                        underlying,//address _indexToken,
                        openPos[i],//uint256 _collateralDelta,
                        openPos[i],//uint256 _sizeDelta,
                        false,//bool _isLong,
                        address(creditProvider,//address _receiver,
                        uint256(udlPrice).sub(uint256(udlPrice).mul(5).div(1000)), //use current price of underlying, 5/1000 slippage? is this needed?
                        openPos[i],//uint256 _minOut
                        referralCode//bytes32 _referralCode
                    );
                    uint balafter = t.balanceOf(address(creditProvider)).mul(b).div(r);
                    uint diffBal = balafter.sub(balBefore);
                    creditProvider.creditPoolBalance(account, allowedTokens[i], diffBal);
                }

                pos_size = uint256(abs(ideal));
            }

            // increase long position by pos_size
            if (pos_size != 0) {

                //TODO: need to add function to exchange to transfer stablecoinds to hedging contract, then from hedging contract to metavault
                uint totalPosValue = pos_size.mul(uint256(udlPrice));
                uint totalPosValueToTransfer = totalPosValue.div(poolLeverage);

                // hedging should fail if not enough stables in exchange
                if (totalStables.mul(poolLeverage) > totalPosValue) {
                    for (uint i=0; i< allowedTokens.length; i++) {

                        /*
                            TODO: transfer login needs to be changed to factor in contract perms for transfering from credit provider
                        */

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
                                t.safeApprove(address(routerAddr), v);

                                //transfer collateral from credit provider to hedging manager and debit pool bal
                                ICollateralManager(
                                    settings.getUdlCollateralManager(
                                        udlFeedAddr
                                    )
                                ).borrowTokensByPreference(
                                    address(this), v, [allowedTokens[i]], [v]
                                )
                            }

                            IPositionManager(positionManagerAddr).increasePosition(
                                [allowedTokens[i], underlying],//address[] memory _path,
                                underlying,//address _indexToken,
                                v,//uint256 _amountIn,
                                v.div(uint256(udlPrice)),//uint256 _minOut, //_minOut can be zero if no swap is required 
                                v.mul(poolLeverage),//uint256 _sizeDelta,
                                true,// bool _isLong
                                uint256(udlPrice).sub(uint256(udlPrice).mul(5).div(1000)),//uint256 _price,
                                referralCode//bytes32 _referralCode
                            );

                            totalPosValueToTransfer = totalPosValueToTransfer.sub(v);
                        }
                    }
                }
            }
        }
    } 
}