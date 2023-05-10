pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/external/d8x/ID8xPerpetualsContractInterface.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/ID8xHedgingManagerFactory.sol";
import "../utils/Convert.sol";


contract D8xHedgingManager is BaseHedgingManager {
    address private orderBookAddr;
    address private perpetualProxy;
    address private d8xHedgingManagerFactoryAddr;
    uint private maxLeverage = 30;
    uint private minLeverage = 1;
    uint private defaultLeverage = 15;
    uint constant _volumeBase = 1e18;

    event PerpOrderSubmitFailed(string reason);
    event PerpOrderSubmitSuccess(int256 amountDec18, int16 leverageInteger);
        
    int256 private constant DECIMALS = 10**18;
    int128 private constant ONE_64x64 = 0x010000000000000000;
    int128 private constant MIN_64x64 = -0x80000000000000000000000000000000;
    int128 private constant MAX_64x64 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    int128 private constant TEN_64x64 = 0xa0000000000000000;

    //TODO: need to find way to map underlying token addrs to iPerpetualId's

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
        d8xHedgingManagerFactoryAddr = deployer.getContractAddress("D8xHedgingManagerFactory");
        (_d8xOrderBookAddr, _perpetualProxy) = ID8xHedgingManagerFactory(d8xHedgingManagerFactoryAddr).getRemoteContractAddresses();
        
        require(_d8xOrderBookAddr != address(0), "bad order book");
        require(_perpetualProxy != address(0), "bad perp proxy");
        
        orderBookAddr = _d8xOrderBookAddr;
        perpetualProxy = _perpetualProxy;
    }

    ID8xPerpetualsContractInterface(perpetualProxy).getLiquidityPools(uint8 _poolFromIdx, uint8 _poolToIdx) external view override returns (LiquidityPoolData[] memory);


    /**
     * Approve the margin-token to be spent by perpetuals contract.
     * Required to trade.
     * @param _amount spend amount
     */
    function approveAmount(address mgnTokenAddr, uint256 _amount) external {
        IERC20(mgnTokenAddr).approve(perpetualProxy, _amount);
    }


    /**
     * Post an order to the order book. Order will be executed by
     * external "keepers".
     * @param _amountDec18 signed amount to be traded
     * @param _leverageInteger leverage (integer), e.g. 2 for 2x leverage
     * @return true if posting order succeeded
     */

    /**
     * @notice
     * Available order flags:
     *  uint32 internal constant MASK_CLOSE_ONLY = 0x80000000;
     *  uint32 internal constant MASK_MARKET_ORDER = 0x40000000;
     *  uint32 internal constant MASK_STOP_ORDER = 0x20000000;
     *  uint32 internal constant MASK_FILL_OR_KILL = 0x10000000;
     *  uint32 internal constant MASK_KEEP_POS_LEVERAGE = 0x08000000;
     *  uint32 internal constant MASK_LIMIT_ORDER = 0x04000000;
     */
    function postOrder(uint24 iPerpetualId, int256 _amountDec18, int16 _leverageInteger) internal returns (bool) {
        require(_leverageInteger >= 0, "invalid lvg");
        int128 fTradeAmount = _fromDec18(_amountDec18);
        int128 fLeverage = _fromInt(int256(_leverageInteger));
        IClientOrder.ClientOrder memory order;
        order.flags = 0x40000000;
        order.iPerpetualId = iPerpetualId;
        order.traderAddr = address(this);
        order.fAmount = fTradeAmount;
        order.fLimitPrice = fTradeAmount > 0 ? MAX_64x64 : int128(0);
        order.fLeverage = fLeverage; // 0 if deposit and trade separate
        order.iDeadline = uint64(block.timestamp + 86400 * 3);
        order.createdTimestamp = uint64(block.timestamp);
        // fields not required:
        //      uint16 brokerFeeTbps;
        //      address brokerAddr;
        //      address referrerAddr;
        //      bytes brokerSignature;
        //      int128 fTriggerPrice;
        //      bytes32 parentChildDigest1;
        //      bytes32 parentChildDigest2;

        // submit order
        //TODO: missing  OrderBookContractInterface, mapping to ID8xPerpetualsContractInterface
        try ID8xPerpetualsContractInterface(orderBookAddr).postOrder(order, bytes("")) {
            emit PerpOrderSubmitSuccess(_amountDec18, _leverageInteger);
            return true;
        } catch Error(string memory reason) {
            emit PerpOrderSubmitFailed(reason);
            return false;
        }
    }

    /**
     * Return margin account information in decimal 18 format
     */
    function getMarginAccount(uint24 iPerpetualId) internal view returns (D18MarginAccount memory) {
        MarginAccount memory acc = ID8xPerpetualsContractInterface(perpetualProxy).getMarginAccount(
            iPerpetualId,
            address(this)
        );
        D18MarginAccount memory accD18;
        accD18.lockedInValueQCD18 = toDec18(acc.fLockedInValueQC); // unrealized value locked-in when trade occurs: price * position size
        accD18.cashCCD18 = toDec18(acc.fCashCC); // cash in collateral currency (base, quote, or quanto)
        accD18.positionSizeBCD18 = toDec18(acc.fPositionBC); // position in base currency (e.g., 1 BTC for BTCUSD)
        accD18.positionId = acc.positionId; // unique id for the position (for given trader, and perpetual).
        return accD18;
    }

    /**
     * Get maximal trade amount for the contract accounting for its current position
     * @param isBuy true if we go long, false if we go short
     * @return signed maximal trade size (negative if resulting position is short, positive otherwise)
     */
    function getMaxTradeAmount(uint24 iPerpetualId, bool isBuy) internal view returns (int256) {
        MarginAccount memory acc = ID8xPerpetualsContractInterface(perpetualProxy).getMarginAccount(
            iPerpetualId,
            address(this)
        );
        int128 fSize = ID8xPerpetualsContractInterface(perpetualProxy).getMaxSignedOpenTradeSizeForPos(
            iPerpetualId,
            acc.fPositionBC,
            isBuy
        );

        if ((isBuy && fSize < 0) || (!isBuy && fSize > 0)) {
            // obsolete with deployment past April 23
            fSize = 0;
        }

        return toDec18(fSize);
    }

    function getAllowedStables() public view returns (address[] memory) {
        address[] memory allowedTokens = settings.getAllowedTokens();
        IVault mvxVault = IVault(mvxVaultAddr);
        uint256 mvxAllowedTokensLen = mvxVault.allWhitelistedTokensLength();
        address[] memory outTokens = new address[](allowedTokens.length);
        uint256 foundCount  = 0;
        for (uint256 i=0;i<allowedTokens.length;i++){
            for (uint j=0;j<mvxAllowedTokensLen;j++){
                address mvxAllowedToken = mvxVault.allWhitelistedTokens(j);
                if (allowedTokens[i] == mvxAllowedToken) {
                    outTokens[i] = allowedTokens[i];
                    foundCount++;
                    continue;
                }
            }
        }

        address[] memory outTokensReal = new address[](foundCount);

        //TODO: need to loop over pools and look for the collateral addrs

        //ID8xPerpetualsContractInterface(perpetualProxy).getPoolCount() external view override returns (uint8);

        //ID8xPerpetualsContractInterface(perpetualProxy).getLiquidityPools(uint8 _poolFromIdx, uint8 _poolToIdx) external view override returns (LiquidityPoolData[] memory);



        uint rIdx = 0;
        for (uint i=0; i<allowedTokens.length; i++) {
            if (outTokens[i] != address(0)) {
                outTokensReal[rIdx] = outTokens[i];
                rIdx++;
            }
        }

        return outTokensReal;
    }

    function getPosSize(address underlying, bool isLong) override public view returns (uint[] memory) {
        address[] memory allowedTokens = getAllowedStables();
        address[] memory _collateralTokens = new address[](allowedTokens.length);
        address[] memory _indexTokens = new address[](allowedTokens.length);
        bool[] memory _isLong = new bool[](allowedTokens.length);

        //TODO: need to use getMaxTradeAmount, and get the `asset id` from the  `oracle` from `underlying`, and map it to looping over the pool ids, 

        //ID8xPerpetualsContractInterface(perpetualProxy).getPoolCount() external view override returns (uint8);


        //ID8xPerpetualsContractInterface(perpetualProxy).getLiquidityPools(uint8 _poolFromIdx, uint8 _poolToIdx) external view override returns (LiquidityPoolData[] memory);

        for (uint i=0; i<allowedTokens.length; i++) {
            
             _collateralTokens[i] = allowedTokens[i];
            _indexTokens[i] = underlying;
            _isLong[i] = isLong;
        }

        uint256[] memory posData = IReader(readerAddr).getPositions(
            mvxVaultAddr,
            address(this),
            _collateralTokens, //need to be the approved stablecoins on dod * [long, short]
            _indexTokens,
            _isLong
        );

        uint[] memory posSize = new uint[](allowedTokens.length);

        for (uint i=0; i<allowedTokens.length; i++) {
            posSize[i] = posData[i*9];
        }

        return posSize;
    }

    function getHedgeExposure(address underlying) override public view returns (int256) {
        address[] memory allowedTokens = getAllowedStables();
        address[] memory _collateralTokens = new address[](allowedTokens.length * 2);
        address[] memory _indexTokens = new address[](allowedTokens.length * 2);
        bool[] memory _isLong = new bool[](allowedTokens.length * 2);

        for (uint i=0; i<allowedTokens.length; i++) {
            
            _collateralTokens[i * 2] = allowedTokens[i];
            _collateralTokens[((i+1) * 2) - 1] = allowedTokens[i];
            
            _indexTokens[i * 2] = underlying;
            _indexTokens[((i+1) * 2) - 1] = underlying;
            
            _isLong[i * 2] = true;
            _isLong[((i+1) * 2) - 1] = false;
        }



        uint256[] memory posData = IReader(readerAddr).getPositions(
            mvxVaultAddr,
            address(this),
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

                if ((_uncovered[i] > 0) && (_uncovered[i] > _holding[i])) {
                    // net short this option, thus does not need to be modified
                    delta = ICollateralManager(
                        settings.getUdlCollateralManager(opt.udlFeed)
                    ).calcDelta(
                        opt,
                        _uncovered[i].sub(_holding[i])
                    );
                }  


                if (_holding[i] > 0){
                    // net long thus needs to multiply by -1
                    delta = ICollateralManager(
                        settings.getUdlCollateralManager(opt.udlFeed)
                    ).calcDelta(
                        opt,
                        _holding[i]
                    ).mul(-1);
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
        return exposure.mul(int(_volumeBase)).div(udlPrice);
    }

    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
    
    function balanceExposure(address udlFeedAddr) override external returns (bool) {
        ExposureData memory exData;
        exData.underlying = UnderlyingFeed(udlFeedAddr).getUnderlyingAddr();
        (, int256 udlPrice) = UnderlyingFeed(udlFeedAddr).getLatestPrice();
        exData.udlPrice = uint256(udlPrice);
        exData.allowedTokens = getAllowedStables();
        exData.totalStables = creditProvider.totalTokenStock();
        exData.totalHedgingStables = totalTokenStock();
        exData.poolLeverage = (settings.isAllowedCustomPoolLeverage(poolAddr) == true) ? IGovernableLiquidityPool(poolAddr).getLeverage() : defaultLeverage;
        require(exData.poolLeverage <= maxLeverage && exData.poolLeverage >= minLeverage, "leverage out of range");
        exData.ideal = idealHedgeExposure(exData.underlying);
        exData.real = getHedgeExposure(exData.underlying).mul(int(_volumeBase)).div(udlPrice);
        exData.diff = exData.ideal.sub(exData.real);

        //dont bother to hedge if delta is below $ val threshold
        if (uint256(MoreMath.abs(exData.diff)).mul(exData.udlPrice).div(_volumeBase) < IGovernableLiquidityPool(poolAddr).getHedgeNotionalThreshold()) {
            return false;
        }


        //close out existing open pos
        if (exData.real > 0) {
            //need to close long position first
            //need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)
            exData.openPos = getPosSize(exData.underlying, true);
            for(uint i=0; i< exData.openPos.length; i++){
                if (exData.openPos[i] > 0) {
                    exData.t = IERC20_2(exData.allowedTokens[i]);
                    exData._pathDecLong = new address[](2);
                    exData._pathDecLong[0] = exData.underlying;
                    exData._pathDecLong[1] = exData.allowedTokens[i];

                    if (_isTestNet == true) {
                        //NOTE: THIS IS NOT ATOMIC, WILL NEED TO MANUALLY TRANSFER ANY RECIEVING STABLECOIN TO CREDIT PROVIDER AND MANUALLY CREDIT POOL BAL IN ANOTHER TX
                        IPositionManager(positionManagerAddr).decreasePositionAndSwap(
                            exData._pathDecLong, //address[] memory _path
                            exData.underlying,//address _indexToken,
                            0,//uint256 _collateralDelta, USD 1e30 mult
                            exData.openPos[i],//uint256 _sizeDelta, USD 1e30 mult
                            true,//bool _isLong,
                            address(creditProvider),//address _receiver,
                            convertPriceAndApplySlippage(exData.udlPrice, false), //uint256 _price, use current price of underlying, 5/1000 slippage? is this needed?, USD 1e30 mult
                            0//uint256(Convert.formatValue(exData.openPos[i], 18, 30)),//uint256 _minOut, TOKEN DECIMALS
                        );
                    } else {
                        IPositionManager(positionManagerAddr).decreasePositionAndSwap(
                            exData._pathDecLong, //address[] memory _path
                            exData.underlying,//address _indexToken,
                            0,//uint256 _collateralDelta, USD 1e30 mult
                            exData.openPos[i],//uint256 _sizeDelta, USD 1e30 mult
                            true,//bool _isLong,
                            address(creditProvider),//address _receiver,
                            convertPriceAndApplySlippage(exData.udlPrice, false), //uint256 _price, use current price of underlying, 5/1000 slippage? is this needed?, USD 1e30 mult
                            0,//uint256(Convert.formatValue(exData.openPos[i], 18, 30)),//uint256 _minOut, TOKEN DECIMALS
                            referralCode//bytes32 _referralCode
                        );
                    }
                }
            }
            
            exData.pos_size = uint256(MoreMath.abs(exData.ideal));
        }

        if (exData.real < 0) {
            // need to close short position first
            // need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)
            exData.openPos = getPosSize(exData.underlying, false);             
            for(uint i=0; i< exData.openPos.length; i++){
                //NOTE: THIS IS NOT ATOMIC, WILL NEED TO MANUALLY TRANSFER ANY RECIEVING STABLECOIN TO CREDIT PROVIDER AND MANUALLY CREDIT POOL BAL IN ANOTHER TX

                if (exData.openPos[i] > 0) {

                    if (_isTestNet) {
                        IPositionManager(positionManagerAddr).decreasePosition(
                            exData.allowedTokens[i],//address _collateralToken,
                            exData.underlying,//address _indexToken,
                            0,//uint256 _collateralDelta,
                            exData.openPos[i],//uint256 _sizeDelta,
                            false,//bool _isLong,
                            address(creditProvider),//address _receiver,
                            convertPriceAndApplySlippage(exData.udlPrice, true)//uint256 _price,
                        );

                    } else {
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
                }
            }

            exData.pos_size = uint256(exData.ideal);
        }

        //open new pos
        if (exData.ideal <= 0) {
            // increase short position by pos_size
            if (exData.pos_size != 0) {
                exData.totalPosValue = exData.pos_size.mul(exData.udlPrice).div(_volumeBase);
                exData.totalPosValueToTransfer = exData.totalPosValue.div(exData.poolLeverage);

                require(
                    getMaxShortLiquidity(udlFeedAddr) >= exData.totalPosValue,
                    "no short hedge liq"
                );

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

                                if (_isTestNet) {                     
                                    IPositionManager(positionManagerAddr).increasePosition(
                                        exData.at,//address[] memory _path,
                                        exData.underlying,//address _indexToken,
                                        v,//uint256 _amountIn, TOKEN DECIMALS
                                        0,//uint256 _minOut, //_minOut can be zero if no swap is required , TOKEN DECIMALS
                                        convertNotitionalValue(v, exData.poolLeverage, exData.b, exData.r),//uint256 _sizeDelta, USD 1e30 mult
                                        false,// bool _isLong
                                        convertPriceAndApplySlippage(exData.udlPrice, false)//uint256 _price USD 1e30 mult
                                    );
                                } else {
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
                                }

                                //back to exchange decimals

                                if (exData.totalPosValueToTransfer > v.mul(exData.r).div(exData.b)) {
                                    exData.totalPosValueToTransfer = exData.totalPosValueToTransfer.sub(v.mul(exData.r).div(exData.b));

                                } else {
                                    exData.totalPosValueToTransfer = 0;
                                }

                                exData.r = 0;
                                exData.b = 0;
                            }                            
                        }
                    }
                }

                return true;
            }
        } else if (exData.ideal > 0) {

            // increase long position by pos_size
            if (exData.pos_size != 0) {
                exData.totalPosValue = exData.pos_size.mul(exData.udlPrice).div(_volumeBase);
                exData.totalPosValueToTransfer = exData.totalPosValue.div(exData.poolLeverage);

                require(
                    getMaxLongLiquidity(udlFeedAddr) >= exData.totalPosValue,
                    "no long hedge liq"
                );

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


                                if (_isTestNet) {  
                                    IPositionManager(positionManagerAddr).increasePosition(
                                        at_s,//address[] memory _path,
                                        exData.underlying,//address _indexToken,
                                        v,//uint256 _amountIn, TOKEN DECIMALS
                                        0,//Convert.formatValue(v.div(exData.udlPrice).mul(exData.b).div(exData.r), 30, 18),//uint256 _minOut, //_minOut can be zero if no swap is required , TOKEN DECIMALS
                                        convertNotitionalValue(v, exData.poolLeverage, exData.b, exData.r),//uint256 _sizeDelta, USD 1e30 mult
                                        true,// bool _isLong
                                        convertPriceAndApplySlippage(exData.udlPrice, true)//uint256 _price, USD 1e30 mult
                                    );
                                } else {
                                    IPositionManager(positionManagerAddr).increasePosition(
                                        at_s,//address[] memory _path,
                                        exData.underlying,//address _indexToken,
                                        v,//uint256 _amountIn, TOKEN DECIMALS
                                        0,//Convert.formatValue(v.div(exData.udlPrice).mul(exData.b).div(exData.r), 30, 18),//uint256 _minOut, //_minOut can be zero if no swap is required , TOKEN DECIMALS
                                        convertNotitionalValue(v, exData.poolLeverage, exData.b, exData.r),//uint256 _sizeDelta, USD 1e30 mult
                                        true,// bool _isLong
                                        convertPriceAndApplySlippage(exData.udlPrice, true),//uint256 _price, USD 1e30 mult
                                        referralCode//bytes32 _referralCode
                                    );
                                }

                                //back to exchange decimals
                                if (exData.totalPosValueToTransfer > v.mul(exData.r).div(exData.b)) {
                                    exData.totalPosValueToTransfer = exData.totalPosValueToTransfer.sub(v.mul(exData.r).div(exData.b));

                                } else {
                                    exData.totalPosValueToTransfer = 0;
                                }
                                exData.r = 0;
                                exData.b = 0;
                            }                             
                        }
                    }
                }

                return true;
            }
        }

        return false;
    }

    function getMaxLongLiquidity(address udlFeedAddr) public view returns (uint v) {
        /*

            - To calculate the available amount of liquidity for long positions:

                        indexToken: the address of the token to long
                        Available amount in tokens: Vault.poolAmounts(indexToken) - Vault.reservedAmounts(indexToken)
                        Available amount in USD: PositionRouter.maxGlobalLongSizes(indexToken) - Vault.guaranteedUsd(indexToken)
                        The available liquidity will be the lower of these two values
                        PositionRouter.maxGlobalLongSizes(indexToken) can be zero, in which case there is no additional cap, and available liquidity is based only on the available amount of tokens
        */

        ExposureData memory exData;
        exData.underlying = UnderlyingFeed(udlFeedAddr).getUnderlyingAddr();
        IVault mvxVault = IVault(mvxVaultAddr);

        uint256 vliq = mvxVault.poolAmounts(exData.underlying).sub(mvxVault.reservedAmounts(exData.underlying));
        uint256 pegliq = IPositionManager(positionManagerAddr).maxGlobalLongSizes(exData.underlying).sub(mvxVault.guaranteedUsd(exData.underlying));

        uint256 totalLiq = MoreMath.min(vliq, pegliq);

        return Convert.formatValue(totalLiq, 18, 30);

    }

    function getMaxShortLiquidity(address udlFeedAddr) public view returns (uint v) {
        /*
            -To calculate the available amount of liquidity for short positions:
                        indexToken: the address of the token to short
                        collateralToken: the address of the stablecoin token to be used as collateral
                        Available amount in tokens: Vault.poolAmounts(collateralToken) - Vault.reservedAmounts(collateralToken)
                        Available amount in USD: PositionRouter.maxGlobalShortSizes(indexToken) - Vault.globalShortSizes(indexToken)
                        The available liquidity will be the lower of these two values
                        PositionRouter.maxGlobalShortSizes(indexToken) can be zero, in which case there is no additional cap, and available liquidity is based only on the available amount of tokens
        */
        address[] memory tokens = getAllowedStables();
        ExposureData memory exData;
        exData.underlying = UnderlyingFeed(udlFeedAddr).getUnderlyingAddr();
        IVault mvxVault = IVault(mvxVaultAddr);
        IPositionManager mvxPositionManager = IPositionManager(positionManagerAddr);
        uint256 totalLiq = 0;

        for(uint i=0; i<tokens.length; i++) {
            uint256 vliq = mvxVault.poolAmounts(tokens[i]).sub(mvxVault.reservedAmounts(tokens[i]));
            uint256 pegliq = mvxPositionManager.maxGlobalShortSizes(exData.underlying).sub(mvxVault.globalShortSizes(exData.underlying));
            totalLiq = totalLiq.add(MoreMath.min(vliq, pegliq));
        }

        return Convert.formatValue(totalLiq, 18, 30);
        
    }

    function totalTokenStock() override public view returns (uint v) {

        address[] memory tokens = getAllowedStables();
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

    /**
     * Convert signed decimal-18 number to ABDK-128x128 format
     * @param x number decimal-18
     * @return ABDK-128x128 number
     */
    function _fromDec18(int256 x) internal pure returns (int128) {
        int256 result = (x * ONE_64x64) / DECIMALS;
        require(x >= MIN_64x64 && x <= MAX_64x64, "result out of range");
        return int128(result);
    }

    /**
     * Convert ABDK-128x128 format to signed decimal-18 number
     * @param x number in ABDK-128x128 format
     * @return decimal 18 (signed)
     */
    function toDec18(int128 x) internal pure returns (int256) {
        return (int256(x) * DECIMALS) / ONE_64x64;
    }

    /**
     * Convert signed 256-bit integer number into signed 64.64-bit fixed point
     * number.  Revert on overflow.
     *
     * @param x signed 256-bit integer number
     * @return signed 64.64-bit fixed point number
     */
    function _fromInt(int256 x) internal pure returns (int128) {
        require(x >= -0x8000000000000000 && x <= 0x7FFFFFFFFFFFFFFF, "ABDK.fromInt");
        return int128(x << 64);
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