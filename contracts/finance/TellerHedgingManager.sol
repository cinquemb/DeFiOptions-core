pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/external/teller/ITellerInterface.sol";
import "../interfaces/IBaseRehypothecationManager.sol";
import "../interfaces/AggregatorV3Interface.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/ITellerHedgingManagerFactory.sol";
import "../utils/Convert.sol";


contract TellerHedgingManager is BaseHedgingManager {
    address private orderBookAddr;
    address private perpetualProxy;
    address private tellerHedgingManagerFactoryAddr;
    uint private maxLeverage = 30;
    uint private minLeverage = 1;
    uint private defaultLeverage = 15;
    uint constant _volumeBase = 1e18;
    address creditToken;

    event PerpOrderSubmitFailed(string reason);
    event PerpOrderSubmitSuccess(int256 amountDec18, int16 leverageInteger);
        
    int256 private constant DECIMALS = 10**18;
    int128 private constant ONE_64x64 = 0x010000000000000000;
    int128 private constant MIN_64x64 = -0x80000000000000000000000000000000;
    int128 private constant MAX_64x64 = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    int128 private constant TEN_64x64 = 0xa0000000000000000;

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
        string underlyingStr;

        address[] at;
        address[] _pathDecLong;
        address[] allowedTokens;
        uint256[] tv;
        int256[] openPos;
        uint24[] perpIds;
        
    }

    constructor(address _deployAddr, address _poolAddr) public {
        poolAddr = _poolAddr;
        Deployer deployer = Deployer(_deployAddr);
        super.initialize(deployer);
        tellerHedgingManagerFactoryAddr = deployer.getContractAddress("TellerHedgingManagerFactory");
        (address _d8xOrderBookAddr,address _perpetualProxy) = ITellerHedgingManagerFactory(tellerHedgingManagerFactoryAddr).getRemoteContractAddresses();
        creditToken = deployer.getContractAddress("CreditToken");
        
        require(_d8xOrderBookAddr != address(0), "bad order book");
        require(_perpetualProxy != address(0), "bad perp proxy");
        
        orderBookAddr = _d8xOrderBookAddr;
        perpetualProxy = _perpetualProxy;
    }

    function pool() override external view returns (address) {
        return poolAddr;
    }

    function getAllowedStables() public view returns (address[] memory) {
        address[] memory outTokensReal = new address[](1);
        outTokensReal[0] = creditToken;
        return outTokensReal;
    }


    function getPosSize(address underlying, bool isLong) override public view returns (uint[] memory) {
        address[] memory allowedTokens = getAllowedStables();
        uint256[] memory posData = new uint256[](allowedTokens.length);
        return posData;
    }

    function getPosSize(string memory underlyingStr, bool isLong) public view returns (int256[] memory, uint24[] memory) {
        address[] memory allowedTokens = getAllowedStables();
        int256[] memory posSize = new int256[](allowedTokens.length);
        uint24[] memory perIds = new uint24[](allowedTokens.length);

        /*
        for (uint i=0; i<allowedTokens.length; i++) {
            uint24 d8xPerpId = getAssetIdsForUnderlying(underlyingStr, allowedTokens[i]);
            ID8xPerpetualsContractInterface.D18MarginAccount memory accD18 = getMarginAccount(d8xPerpId);

            posSize[i] = accD18.positionSizeBCD18;
            perIds[i] = d8xPerpId;
        }*/


        return (posSize, perIds);
    }

    function getMaxPosSize(string memory underlyingStr, bool isLong) public view returns (int256) {
        address[] memory allowedTokens = getAllowedStables();
        int256[] memory posData = new int256[](allowedTokens.length);

        /*
        for (uint i=0; i<allowedTokens.length; i++) {
            
            uint24 d8xPerpId = getAssetIdsForUnderlying(underlyingStr, allowedTokens[i]);
            posData[i] = getMaxTradeAmount(d8xPerpId, isLong);
        }
        */

        int256 totalExposure = 0;
        for (uint i=0; i<(allowedTokens.length); i++) {
            totalExposure = totalExposure.add(posData[i]);
        }

        return totalExposure;
    }

    function getHedgeExposure(address underlying) override public view returns (int256) {
        return 0;
    }

    function getHedgeExposure(string memory underlyingStr) public view returns (int256) {
        address[] memory allowedTokens = getAllowedStables();
        int256[] memory posData = new int256[](allowedTokens.length);

        for (uint i=0; i<allowedTokens.length; i++) {
            
            //uint24 d8xPerpId = getAssetIdsForUnderlying(underlyingStr, allowedTokens[i]);
            //ID8xPerpetualsContractInterface.D18MarginAccount memory accD18 = getMarginAccount(d8xPerpId);
            //posData[i] = accD18.positionSizeBCD18;
        }

        int256 totalExposure = 0;
        for (uint i=0; i<(allowedTokens.length); i++) {
            totalExposure = totalExposure.add(posData[i]);
        }

        return totalExposure;
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
        string memory underlyingStr = AggregatorV3Interface(UnderlyingFeed(udlFeedAddr).getUnderlyingAggAddr()).description();

        int256 exposure = getHedgeExposure(underlyingStr);
        return exposure.mul(int(_volumeBase)).div(udlPrice);
    }
    
    function balanceExposure(address udlFeedAddr) override external returns (bool) {
        ExposureData memory exData;
        exData.underlying = UnderlyingFeed(udlFeedAddr).getUnderlyingAddr();
        exData.underlyingStr = AggregatorV3Interface(UnderlyingFeed(udlFeedAddr).getUnderlyingAggAddr()).description();
        (, int256 udlPrice) = UnderlyingFeed(udlFeedAddr).getLatestPrice();
        exData.udlPrice = uint256(udlPrice);
        exData.allowedTokens = getAllowedStables();
        exData.totalStables = creditProvider.totalTokenStock();
        exData.totalHedgingStables = totalTokenStock();
        exData.poolLeverage = (settings.isAllowedCustomPoolLeverage(poolAddr) == true) ? IGovernableLiquidityPool(poolAddr).getLeverage() : defaultLeverage;
        require(exData.poolLeverage <= maxLeverage && exData.poolLeverage >= minLeverage, "leverage out of range");
        exData.ideal = idealHedgeExposure(exData.underlying);
        exData.real = getHedgeExposure(exData.underlyingStr).mul(int(_volumeBase)).div(udlPrice);
        exData.diff = exData.ideal.sub(exData.real);

        //dont bother to hedge if delta is below $ val threshold
        if (uint256(MoreMath.abs(exData.diff)).mul(exData.udlPrice).div(_volumeBase) < IGovernableLiquidityPool(poolAddr).getHedgeNotionalThreshold()) {
            return false;
        }


        //close out existing open pos
        if (exData.real != 0) {
            //need to close long position first
            //need to loop over all available exchange stablecoins, or need to deposit underlying int to vault (if there is a vault for it)
            (exData.openPos, exData.perpIds) = getPosSize(exData.underlyingStr, true);
            for(uint i=0; i< exData.openPos.length; i++){
                if (exData.openPos[i] != 0) {
                    //postOrder(exData.perpIds[i], exData.openPos[i], 0, 0x80000000);
                }
            }
            

            if (exData.real > 0) {
                exData.pos_size = uint256(MoreMath.abs(exData.ideal));
            }

            if (exData.real < 0) {
                exData.pos_size = uint256(exData.ideal);
            }
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

                                if (exData.t.allowance(address(this), perpetualProxy) > 0) {
                                    exData.t.safeApprove(perpetualProxy, 0);
                                }
                                exData.t.safeApprove(perpetualProxy, v.mul(exData.r).div(exData.b));

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

                                //uint24 d8xPerpId = getAssetIdsForUnderlying(exData.underlyingStr, exData.allowedTokens[i]);
                                //postOrder(d8xPerpId, int256(v.mul(exData.r).div(exData.b)).mul(-1), int16(exData.poolLeverage), 0x40000000);

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
                                if (exData.t.allowance(address(this), perpetualProxy) > 0) {
                                    exData.t.safeApprove(perpetualProxy, 0);
                                }
                                exData.t.safeApprove(perpetualProxy, v.mul(exData.r).div(exData.b));

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


                                //uint24 d8xPerpId = getAssetIdsForUnderlying(exData.underlyingStr, exData.allowedTokens[i]);
                                //postOrder(d8xPerpId, int256(v.mul(exData.r).div(exData.b)), int16(exData.poolLeverage), 0x40000000);

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
        ExposureData memory exData;
        exData.underlyingStr = AggregatorV3Interface(UnderlyingFeed(udlFeedAddr).getUnderlyingAggAddr()).description();

        return uint256(getMaxPosSize(exData.underlyingStr, true));

    }

    function getMaxShortLiquidity(address udlFeedAddr) public view returns (uint v) {
        ExposureData memory exData;
        exData.underlyingStr = AggregatorV3Interface(UnderlyingFeed(udlFeedAddr).getUnderlyingAggAddr()).description();

        return uint256(MoreMath.abs(getMaxPosSize(exData.underlyingStr, false)));
        
    }

    function totalTokenStock() override public view returns (uint v) {

        address[] memory tokens = getAllowedStables();
        for (uint i = 0; i < tokens.length; i++) {
            (uint r, uint b) = settings.getTokenRate(tokens[i]);
            uint value = IERC20_2(tokens[i]).balanceOf(address(this));
            v = v.add(value.mul(b).div(r));
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

    function findAllowedUnderlying(string memory underlyingStr, bytes32[] memory d8xAssetIds) private pure returns (bool){

        for (uint i = 0; i < d8xAssetIds.length; i++) {
            if(keccak256(abi.encodePacked((underlyingStr))) == keccak256(abi.encodePacked((bytes32ToString(d8xAssetIds[i]))))) {
                return true;
            }
        }

        return false;
    }

    function bytes32ToString(bytes32 x) private pure returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
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
}