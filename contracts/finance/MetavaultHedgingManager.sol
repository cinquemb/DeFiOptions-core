pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/external/metavault/IPositionManager.sol";
import "../interfaces/external/metavault/IReader.sol";
import "../interfaces/external/metavault/IRouter.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/IMetavaultHedgingManagerFactory.sol";
import "../utils/Convert.sol";

contract MetavaultHedgingManager is BaseHedgingManager {
    address private positionManagerAddr;
    address private readerAddr;
    address private mvxRouter;
    address private metavaultHedgingManagerFactoryAddr;
    uint private maxLeverage = 30;
    uint private minLeverage = 1;
    uint private defaultLeverage = 15;

    bytes32 private referralCode;

    struct ExposureData {
        IERC20_2 t;

        int256 diff;
        int256 real;
        int256 ideal;

        uint256 r;
        uint256 b;
        
        uint256 pos_size;
        uint256 udlPrice;
        uint256 totalStables;
        uint256 poolLeverage;
        uint256 totalPosValue;
        uint256 totalHedgingStables;
        uint256 totalPosValueToTransfer;
        
        address underlying;
        
        address[] at;
        address[] _pathDecLong;
        address[] allowedTokens;
        uint256[] tv;
        uint256[] openPos;
        
    }

    constructor(address _deployAddr, address _poolAddr) public {
        poolAddr = _poolAddr;
        Deployer deployer = Deployer(_deployAddr);
        super.initialize(deployer);
        metavaultHedgingManagerFactoryAddr = deployer.getContractAddress("MetavaultHedgingManagerFactory");
        (positionManagerAddr, readerAddr,  referralCode) = IMetavaultHedgingManagerFactory(metavaultHedgingManagerFactoryAddr).getRemoteContractAddresses();
        require(positionManagerAddr != address(0), "bad position manager");
        require(readerAddr != address(0), "bad reader");
        mvxRouter = IPositionManager(positionManagerAddr).router();
        IRouter(mvxRouter).approvePlugin(positionManagerAddr);

    }

    function getPosSize(address underlying, bool isLong) override public view returns (uint[] memory) {
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
            poolAddr,
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

    function getHedgeExposure(address underlying) override public view returns (int256) {
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
            poolAddr,
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
    

    function idealHedgeExposure(address underlying) override public view returns (int256) {
        // look at order book for poolAddr and compute the delta for the given underlying (depening on net positioning of the options outstanding and the side of the trade the poolAddr is on)
        (,address[] memory _tokens, uint[] memory _holding,, uint[] memory _uncovered,, address[] memory _underlying) = exchange.getBook(poolAddr);

        int totalDelta = 0;
        for (uint i = 0; i < _tokens.length; i++) {
            address _tk = _tokens[i];
            IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);
            if (_underlying[i] == underlying){
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
    
    function realHedgeExposure(address udlFeedAddr) override public view returns (int256) {
        // look at metavault exposure for underlying, and divide by asset price
        (, int256 udlPrice) = UnderlyingFeed(udlFeedAddr).getLatestPrice();
        int256 exposure = getHedgeExposure(UnderlyingFeed(udlFeedAddr).getUnderlyingAddr());
        return exposure.div(udlPrice);
    }
    
    function balanceExposure(address udlFeedAddr) override external returns (bool) {
        ExposureData memory exData;
        exData.underlying = UnderlyingFeed(udlFeedAddr).getUnderlyingAddr();
        exData.ideal = idealHedgeExposure(exData.underlying);
        exData.real = realHedgeExposure(exData.underlying);
        exData.diff = exData.ideal - exData.real;
        exData.allowedTokens = settings.getAllowedTokens();
        exData.totalStables = creditProvider.totalTokenStock();

        exData.poolLeverage = (settings.isAllowedCustomPoolLeverage(poolAddr) == true) ? IGovernableLiquidityPool(poolAddr).getLeverage() : defaultLeverage;


        require(exData.poolLeverage <= maxLeverage && exData.poolLeverage >= minLeverage, "leverage out of range");

        exData.totalHedgingStables = totalTokenStock();

        (, int256 udlPrice) = UnderlyingFeed(udlFeedAddr).getLatestPrice();
        exData.udlPrice = uint256(udlPrice);
        exData.openPos = getPosSize(exData.underlying, true);

        if (exData.ideal >= 0) {
            exData.pos_size = uint256(MoreMath.abs(exData.diff));
            if (exData.real > 0) {
                //need to close long position first
                //need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)
                for(uint i=0; i< exData.openPos.length; i++){
                    exData.t = IERC20_2(exData.allowedTokens[i]);
                    exData._pathDecLong = new address[](2);
                    exData._pathDecLong[0] = exData.underlying;
                    exData._pathDecLong[1] = exData.allowedTokens[i];

                    //NOTE: THIS IS NOT ATOMIC, WILL NEED TO MANUALLY TRANSFER ANY RECIEVING STABLECOIN TO CREDIT PROVIDER AND MANUALLY CREDIT POOL BAL IN ANOTHER TX
                    IPositionManager(positionManagerAddr).decreasePositionAndSwap(
                        exData._pathDecLong, //address[] memory _path
                        exData.underlying,//address _indexToken,
                        0,//uint256 _collateralDelta, USD 1e30 mult
                        exData.openPos[i],//uint256 _sizeDelta, USD 1e30 mult
                        true,//bool _isLong,
                        address(creditProvider),//address _receiver,
                        convertPriceAndApplySlippage(exData.udlPrice, false), //uint256 _price, use current price of underlying, 5/1000 slippage? is this needed?, USD 1e30 mult
                        uint256(Convert.formatValue(exData.openPos[i], 18, 30)),//uint256 _minOut, TOKEN DECIMALS
                        referralCode//bytes32 _referralCode
                    );
                }
                
                exData.pos_size = uint256(exData.ideal);
            }
            
            // increase short position by pos_size
            if (exData.pos_size != 0) {
                exData.totalPosValue = exData.pos_size.mul(exData.udlPrice);
                exData.totalPosValueToTransfer = exData.totalPosValue.div(exData.poolLeverage);

                // hedging should fail if not enough stables in exchange
                if (exData.totalStables.mul(exData.poolLeverage) > exData.totalPosValue) {
                    for (uint i=0; i< exData.allowedTokens.length; i++) {

                        if (exData.totalPosValueToTransfer > 0) {
                            exData.t = IERC20_2(exData.allowedTokens[i]);
                            
                            (exData.r, exData.b) = settings.getTokenRate(exData.allowedTokens[i]);
                            if (exData.b != 0) {
                                uint v = MoreMath.min(
                                    exData.totalPosValueToTransfer, 
                                    exData.t.balanceOf(address(creditProvider)).mul(exData.b).div(exData.r)
                                );

                                //.mul(b).div(r); //convert to exchange decimals

                                if (exData.t.allowance(address(this), mvxRouter) > 0) {
                                    exData.t.safeApprove(mvxRouter, 0);
                                }
                                exData.t.safeApprove(mvxRouter, v.mul(exData.r).div(exData.b));

                                //transfer collateral from credit provider to hedging manager and debit pool bal
                                exData.at = new address[](1);
                                exData.at[0] = exData.allowedTokens[i];

                                exData.tv = new uint[](1);
                                exData.tv[0] = v;


                                if (exData.totalHedgingStables < exData.totalPosValueToTransfer){
                                    ICollateralManager(
                                        settings.getUdlCollateralManager(
                                            udlFeedAddr
                                        )
                                    ).borrowTokensByPreference(
                                        address(this), poolAddr, v, exData.at, exData.tv
                                    );
                                }

                                v = v.mul(exData.r).div(exData.b);//converts to token decimals

                                IPositionManager(positionManagerAddr).increasePosition(
                                    exData.at,//address[] memory _path,
                                    exData.underlying,//address _indexToken,
                                    v,//uint256 _amountIn, TOKEN DECIMALS
                                    0,//uint256 _minOut, //_minOut can be zero if no swap is required , TOKEN DECIMALS
                                    convertNotitionalValue(v, exData.poolLeverage, exData.b, exData.r),//uint256 _sizeDelta, USD 1e30 mult
                                    false,// bool _isLong
                                    convertPriceAndApplySlippage(exData.udlPrice, false),//uint256 _price, USD 1e30 mult
                                    referralCode//bytes32 _referralCode
                                );

                                //back to exchange decimals
                                exData.totalPosValueToTransfer = exData.totalPosValueToTransfer.sub(v.mul(exData.r).div(exData.b));

                                exData.r = 0;
                                exData.b = 0;
                            }                            
                        }
                    }
                }
            }
        } else if (exData.ideal < 0) {
            exData.pos_size = uint256(MoreMath.abs(exData.diff));
            if (exData.real < 0) {
                // need to close short position first
                // need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)                
                for(uint i=0; i< exData.openPos.length; i++){
                    //NOTE: THIS IS NOT ATOMIC, WILL NEED TO MANUALLY TRANSFER ANY RECIEVING STABLECOIN TO CREDIT PROVIDER AND MANUALLY CREDIT POOL BAL IN ANOTHER TX
                    IPositionManager(positionManagerAddr).decreasePosition(
                        exData.allowedTokens[i],//address _collateralToken,
                        exData.underlying,//address _indexToken,
                        0,//uint256 _collateralDelta,
                        exData.openPos[i],//uint256 _sizeDelta,
                        false,//bool _isLong,
                        address(creditProvider),//address _receiver,
                        convertPriceAndApplySlippage(exData.udlPrice, true),//uint256 _price,
                        referralCode//bytes32 _referralCode
                    );
                }

                exData.pos_size = uint256(MoreMath.abs(exData.ideal));
            }

            // increase long position by pos_size
            if (exData.pos_size != 0) {
                exData.totalPosValue = exData.pos_size.mul(exData.udlPrice);
                exData.totalPosValueToTransfer = exData.totalPosValue.div(exData.poolLeverage);

                // hedging should fail if not enough stables in exchange
                if (exData.totalStables.mul(exData.poolLeverage) > exData.totalPosValue) {
                    for (uint i=0; i< exData.allowedTokens.length; i++) {

                        if (exData.totalPosValueToTransfer > 0) {
                            exData.t = IERC20_2(exData.allowedTokens[i]);
                            
                            (exData.r, exData.b) = settings.getTokenRate(exData.allowedTokens[i]);
                            if (exData.b != 0) {
                                uint v = MoreMath.min(
                                    exData.totalPosValueToTransfer,
                                    exData.t.balanceOf(address(creditProvider)).mul(exData.b).div(exData.r)
                                );
                                if (exData.t.allowance(address(this), mvxRouter) > 0) {
                                    exData.t.safeApprove(mvxRouter, 0);
                                }
                                exData.t.safeApprove(mvxRouter, v.mul(exData.r).div(exData.b));

                                //transfer collateral from credit provider to hedging manager and debit pool bal
                                exData.at = new address[](1);
                                address[] memory at_s = new address[](2);
                                exData.at[0] = exData.allowedTokens[i];
                                
                                at_s[0] = exData.allowedTokens[i];
                                at_s[1] = exData.underlying;

                                exData.tv = new uint[](1);
                                exData.tv[0] = v;

                                if (exData.totalHedgingStables < exData.totalPosValueToTransfer){
                                    ICollateralManager(
                                        settings.getUdlCollateralManager(
                                            udlFeedAddr
                                        )
                                    ).borrowTokensByPreference(
                                        address(this), poolAddr, v, exData.at, exData.tv
                                    );
                                }

                                v = v.mul(exData.r).div(exData.b);//converts to token decimals

                                IPositionManager(positionManagerAddr).increasePosition(
                                    at_s,//address[] memory _path,
                                    exData.underlying,//address _indexToken,
                                    v,//uint256 _amountIn, TOKEN DECIMALS
                                    Convert.formatValue(v.div(exData.udlPrice).mul(exData.b).div(exData.r), 30, 18),//uint256 _minOut, //_minOut can be zero if no swap is required , TOKEN DECIMALS
                                    convertNotitionalValue(v, exData.poolLeverage, exData.b, exData.r),//uint256 _sizeDelta, USD 1e30 mult
                                    true,// bool _isLong
                                    convertPriceAndApplySlippage(exData.udlPrice, true),//uint256 _price, USD 1e30 mult
                                    referralCode//bytes32 _referralCode
                                );

                                //back to exchange decimals
                                exData.totalPosValueToTransfer = exData.totalPosValueToTransfer.sub(v.mul(exData.r).div(exData.b));
                                exData.r = 0;
                                exData.b = 0;
                            }                             
                        }
                    }
                }
            }
        }
    }

    function totalTokenStock() override public view returns (uint v) {

        address[] memory tokens = settings.getAllowedTokens();
        for (uint i = 0; i < tokens.length; i++) {
            (uint r, uint b) = settings.getTokenRate(tokens[i]);
            uint value = IERC20_2(tokens[i]).balanceOf(address(this));
            v = v.add(value.mul(b).div(r));
        }
    }

    function convertNotitionalValue(uint256 value, uint256 multiplier, uint256 b, uint256 r) pure internal returns (uint256) {
        return Convert.formatValue(value.mul(multiplier).mul(b).div(r), 30, 18);
    }

    function convertPriceAndApplySlippage(uint256 value, bool isAdd) pure internal returns (uint256) {
        if (isAdd) {
            return uint256(Convert.formatValue(value.add(value.mul(3).div(1000)), 30, 18));
        } else {
            return uint256(Convert.formatValue(value.sub(value.mul(3).div(1000)), 30, 18));
        }

    }

    function transferTokensToCreditProvider(address tokenAddr) override external {
        //this needs to be used if/when liquidations happen and tokens sent from external contracts end up here
        uint value = IERC20_2(tokenAddr).balanceOf(address(this));
        if (value > 0) {
            IERC20_2(tokenAddr).safeTransfer(address(creditProvider), value);
            creditProvider.creditPoolBalance(poolAddr, tokenAddr, value);
        }
    }
}