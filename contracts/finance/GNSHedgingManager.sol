/*

- must use DAI

- TOOD: NEED TO MAP UNDERLYING TOKENS ON NETWORK TO PAIR INDEX

*/

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/external/gains_network/IGFarmTradingStorageV5.sol";
import "../interfaces/external/gains_network/IGNSTradingV6_2.sol";
import "../interfaces/external/gains_network/IGNSPairInfosV6_1.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/IGNSHedgingmanagerFactory.sol";
import "../utils/Convert.sol";


contract GNSHedgingManager is BaseHedgingManager {
    address private dai;
    address private referrer;
    address private gnsTradingAddr;
    address private gnsPairInfoAddr;
    address private gnsFarmTradingStorageAddr;
    address private gnsHedgingManagerFactoryAddr;

    uint private maxLeverage = 150;
    uint private minLeverage = 4;
    uint private defaultLeverage = 15;
    uint MAX_UINT = uint(-1);
    uint PRECISION = 1e10;

    struct ExposureData {
        IERC20_2 t;

        int256 diff;
        int256 real;
        int256 ideal;

        uint256 r;
        uint256 b;
        
        uint256 pos_size;
        uint256 diffBal;
        uint256 balAfter;
        uint256 balBefore;
        uint256 udlPrice;
        uint256 pairIndex;
        uint256 totalStables;
        uint256 poolLeverage;
        uint256 totalPosValue;
        uint256 totalPosValueToTransfer;
        
        address underlying;

        bool hasClosed;

        address[] at;
        address[] allowedTokens;
        uint256[] tv;
        
    }

    mapping(string => uint) pairIndexMap;

    //https://gains-network.gitbook.io/docs-home/what-is-gains-network/contract-addresses
    constructor(address _deployAddr, address _poolAddr) public {
        Deployer deployer = Deployer(_deployAddr);
        super.initialize(deployer);
        gnsHedgingManagerFactoryAddr = deployer.getContractAddress("GNSHedgingManagerFactory");
        gnsTradingAddr = IGNSHedgingManagerFactory(gnsHedgingManagerFactoryAddr)._gnsTradingAddr();
        gnsPairInfoAddr = IGNSHedgingManagerFactory(gnsHedgingManagerFactoryAddr)._gnsPairInfoAddr();
        gnsFarmTradingStorageAddr = IGNSHedgingManagerFactory(gnsHedgingManagerFactoryAddr)._gnsFarmTradingStorageAddr();
        referrer = IGNSHedgingManagerFactory(gnsHedgingManagerFactoryAddr)._referrer();
        dai = IGNSHedgingManagerFactory(gnsHedgingManagerFactoryAddr)._daiAddr();
        poolAddr = _poolAddr;

        //off by 1 on purpose
        //https://gains-network.gitbook.io/docs-home/gtrade-leveraged-trading/pair-list
        pairIndexMap["BTC/USD"] = 1;
        pairIndexMap["ETH/USD"] = 2;
        pairIndexMap["LINK/USD"] = 3;
        pairIndexMap["DOGE/USD"] = 4;
        pairIndexMap["MATIC/USD"] = 5;
        pairIndexMap["ADA/USD"] = 6;
        pairIndexMap["SUSHI/USD"] = 7;
        pairIndexMap["AAVE/USD"] = 8;
        pairIndexMap["MATIC/USD"] = 9;
        pairIndexMap["ADA/USD"] = 10;
        pairIndexMap["SUSHI/USD"] = 11;
        pairIndexMap["AAVE/USD"] = 12;
    }

    function getPosSize(address underlying, bool isLong) override public view returns (uint[] memory) {
        uint[] memory data = new uint[](1);
        return data;
    }

    function getHedgeExposure(address underlying) override public view returns (int256) {
        /*

        - get Position info
            - I think if you go to this function 38. openTradesCount(address, pair_index) you will get back the index of your trade (from your 3 slots, so 0, 1 or 2)
                https://polygonscan.com/address/0xaee4d11a16B2bc65EDD6416Fb626EB404a6D65BD#readContract#F38
            - Then the function just above it 37. openTrades(address, pair_index, index (the one you got back from the first))

            - https://polygonscan.com/address/0xaee4d11a16B2bc65EDD6416Fb626EB404a6D65BD#readContract#F37

        */
        uint256 pairIndexOffByOne = pairIndexMap[UnderlyingFeed(underlying).symbol()];
        require(pairIndexOffByOne > 0, "no pair available");
        uint256 pairIndex = pairIndexOffByOne.sub(1);


        uint256 tradeIdx = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTradesCount(address(this), pairIndex);
        IGFarmTradingStorageV5.Trade memory tradeData = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTrades(address(this), pairIndex, tradeIdx);
        IGFarmTradingStorageV5.TradeInfo memory tradeInfoData = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTradesInfo(address(this), pairIndex, tradeIdx);

        return (tradeData.buy == true) ? int256(tradeInfoData.openInterestDai) : int256(tradeInfoData.openInterestDai).mul(-1);
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
        int256 exposure = getHedgeExposure(udlFeedAddr);
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

        exData.pairIndex = pairIndexMap[UnderlyingFeed(udlFeedAddr).symbol()];
        require(exData.pairIndex > 0, "cannot hedge underlying");
        exData.pairIndex = exData.pairIndex.sub(1);

        exData.poolLeverage = (settings.isAllowedCustomPoolLeverage(poolAddr) == true) ? IGovernableLiquidityPool(poolAddr).getLeverage() : defaultLeverage;


        require(exData.poolLeverage <= maxLeverage && exData.poolLeverage >= minLeverage, "leverage out of range");

        (, int256 udlPrice) = UnderlyingFeed(udlFeedAddr).getLatestPrice();
        exData.udlPrice = uint256(udlPrice);

        //TODO: min trade size is 1500 dai

        if (exData.ideal >= 0) {
            exData.pos_size = uint256(MoreMath.abs(exData.diff));
            if (exData.real > 0) {
                //need to close long position first
                uint256 tradeIdx = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTradesCount(address(this), exData.pairIndex);
                //NOTE: THIS IS NOT ATOMIC, WILL NEED TO MANUALLY TRANSFER ANY RECIEVING DAI TO CREDIT PROVIDER AND MANUALLY CREDIT POOL BAL IN ANOTHER TX
                IGNSTradingV6_2(gnsTradingAddr).closeTradeMarket(
                    exData.pairIndex,
                    tradeIdx
                );
                exData.pos_size = uint256(exData.ideal);
                exData.hasClosed = true;

            }
            
            // increase short position by pos_size
            if (exData.pos_size != 0) {
                exData.t = IERC20_2(dai);
                uint256 daiBal = exData.t.balanceOf(address(this));
                exData.totalPosValue = exData.pos_size.mul(exData.udlPrice);
                exData.totalPosValueToTransfer = exData.totalPosValue.div(exData.poolLeverage);

                // hedging should fail if not enough stables in exchange
                ///TODO: IF NO DAI, SHOULD SWAP INTO DAI
                if (exData.totalStables.mul(exData.poolLeverage) > exData.totalPosValue) {

                    if (exData.totalPosValueToTransfer > 0) {                        
                        uint v = MoreMath.min(
                            exData.totalPosValueToTransfer,
                            exData.t.balanceOf(address(creditProvider))
                        );
                        if (exData.t.allowance(address(this), gnsTradingAddr) > 0) {
                            exData.t.safeApprove(gnsTradingAddr, 0);
                        }
                        exData.t.safeApprove(gnsTradingAddr, v);

                        //transfer collateral from credit provider to hedging manager and debit pool bal
                        exData.at = new address[](1);
                        exData.at[0] = dai;

                        exData.tv = new uint[](1);
                        exData.tv[0] = v;

                        if (daiBal < exData.totalPosValueToTransfer) {
                            ICollateralManager(
                                settings.getUdlCollateralManager(
                                    udlFeedAddr
                                )
                            ).borrowTokensByPreference(
                                address(this), poolAddr, v, exData.at, exData.tv
                            );
                        }

                        if (exData.hasClosed == false) {
                            uint256 tradeIdx = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTradesCount(address(this), exData.pairIndex);
                            IGNSTradingV6_2(gnsTradingAddr).closeTradeMarket(
                                exData.pairIndex,
                                tradeIdx
                            );
                        }

                        (uint priceImpactP, uint priceAfterImpact) = IGNSPairInfosV6_1(gnsPairInfoAddr).getTradePriceImpact(
                            exData.udlPrice.mul(PRECISION).div(1e18),//uint openPrice,        // PRECISION
                            exData.pairIndex,
                            false,//bool long,
                            exData.totalPosValue // 1e18 (DAI)
                        ); /*external view returns(
                            uint priceImpactP,     // PRECISION (%)
                            uint priceAfterImpact  // PRECISION
                        )*/

                        uint256 tradeIdx = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTradesCount(address(this), exData.pairIndex);

                        //SAMPLE TX OPEN: https://polygonscan.com/tx/0x5c593b45f2d5e459516666e54c942f23ff3c3991f2a33cde7570b43dd997ee43

                        StorageInterfaceV5.Trade memory t = StorageInterfaceV5.Trade(
                            address(this),
                            exData.pairIndex,
                            tradeIdx,
                            0,//uint initialPosToken,       // 1e18
                            exData.totalPosValueToTransfer,//uint positionSizeDai,       // 1e18
                            exData.udlPrice.mul(PRECISION).div(1e18),//uint openPrice,             // PRECISION
                            false,//bool buy,
                            exData.poolLeverage,//uint leverage,
                            0,//uint tp,                    // PRECISION
                            MAX_UINT//uint sl                    // PRECISION
                        );

                        NftRewardsInterfaceV6.OpenLimitOrderType orderType = NftRewardsInterfaceV6.OpenLimitOrderType(0);

                        IGNSTradingV6_2(gnsTradingAddr).openTrade(
                            t,//StorageInterfaceV5.Trade memory t,
                            orderType,//NftRewardsInterfaceV6.OpenLimitOrderType orderType, // LEGACY => market
                            0,//uint spreadReductionId
                            priceImpactP, // for market orders only
                            referrer
                        );
                    }
                }
            }
        } else if (exData.ideal < 0) {
            exData.pos_size = uint256(MoreMath.abs(exData.diff));
            if (exData.real < 0) {
                // need to close short position first
                uint256 tradeIdx = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTradesCount(address(this), exData.pairIndex);
                //NOTE: THIS IS NOT ATOMIC, WILL NEED TO MANUALLY TRANSFER ANY RECIEVING DAI TO CREDIT PROVIDER AND MANUALLY CREDIT POOL BAL IN ANOTHER TX
                IGNSTradingV6_2(gnsTradingAddr).closeTradeMarket(
                    exData.pairIndex,
                    tradeIdx
                );
                exData.pos_size = uint256(exData.ideal);
                exData.hasClosed = true;
            }

            // increase long position by pos_size
            if (exData.pos_size != 0) {
                exData.totalPosValue = exData.pos_size.mul(exData.udlPrice);
                exData.t = IERC20_2(dai);
                uint256 daiBal = exData.t.balanceOf(address(this));

                exData.totalPosValueToTransfer = exData.totalPosValue.div(exData.poolLeverage);

                // hedging should fail if not enough stables in exchange
                ///TODO: IF NO DAI, SHOULD SWAP INTO DAI
                if (exData.totalStables.mul(exData.poolLeverage) > exData.totalPosValue) {

                    if (exData.totalPosValueToTransfer > 0) {                        
                        uint v = MoreMath.min(
                            exData.totalPosValueToTransfer,
                            exData.t.balanceOf(address(creditProvider))
                        );
                        if (exData.t.allowance(address(this), gnsTradingAddr) > 0) {
                            exData.t.safeApprove(gnsTradingAddr, 0);
                        }
                        exData.t.safeApprove(gnsTradingAddr, v);

                        //transfer collateral from credit provider to hedging manager and debit pool bal
                        exData.at = new address[](1);
                        exData.at[0] = dai;

                        exData.tv = new uint[](1);
                        exData.tv[0] = v;

                        if (daiBal < exData.totalPosValueToTransfer) {
                            ICollateralManager(
                                settings.getUdlCollateralManager(
                                    udlFeedAddr
                                )
                            ).borrowTokensByPreference(
                                address(this), poolAddr, v, exData.at, exData.tv
                            );
                        }

                        if (exData.hasClosed == false) {
                            uint256 tradeIdx = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTradesCount(address(this), exData.pairIndex);
                            IGNSTradingV6_2(gnsTradingAddr).closeTradeMarket(
                                exData.pairIndex,
                                tradeIdx
                            );
                        }

                        (uint priceImpactP, uint priceAfterImpact) = IGNSPairInfosV6_1(gnsPairInfoAddr).getTradePriceImpact(
                            exData.udlPrice.mul(PRECISION).div(1e18),//uint openPrice,        // PRECISION
                            exData.pairIndex,
                            true,//bool long,
                            exData.totalPosValue // 1e18 (DAI)
                        ); /*external view returns(
                            uint priceImpactP,     // PRECISION (%)
                            uint priceAfterImpact  // PRECISION
                        )*/

                        uint256 tradeIdx = IGFarmTradingStorageV5(gnsFarmTradingStorageAddr).openTradesCount(address(this), exData.pairIndex);

                        //SAMPLE TX OPEN: https://polygonscan.com/tx/0x5c593b45f2d5e459516666e54c942f23ff3c3991f2a33cde7570b43dd997ee43

                        StorageInterfaceV5.Trade memory t = StorageInterfaceV5.Trade(
                            address(this),
                            exData.pairIndex,
                            tradeIdx,
                            0,//uint initialPosToken,       // 1e18
                            exData.totalPosValueToTransfer,//uint positionSizeDai,       // 1e18
                            exData.udlPrice.mul(PRECISION).div(1e18),//uint openPrice,             // PRECISION
                            true,//bool buy,
                            exData.poolLeverage,//uint leverage,
                            MAX_UINT,//uint tp,                    // PRECISION
                            0//uint sl                    // PRECISION
                        );

                        NftRewardsInterfaceV6.OpenLimitOrderType orderType = NftRewardsInterfaceV6.OpenLimitOrderType(0);

                        IGNSTradingV6_2(gnsTradingAddr).openTrade(
                            t,//StorageInterfaceV5.Trade memory t,
                            orderType,//NftRewardsInterfaceV6.OpenLimitOrderType orderType, // LEGACY => market
                            0,//uint spreadReductionId
                            priceImpactP, // for market orders only
                            referrer
                        );
                    }
                }
            }
        }
    }

    function transferTokensToCreditProvider(address tokenAddr) override external {
        //this needs to be used if/when liquidations happen and tokens sent from external contracts end up here
        uint value = IERC20_2(tokenAddr).balanceOf(address(this));
        IERC20_2(tokenAddr).safeTransfer(address(creditProvider), value);
        creditProvider.creditPoolBalance(poolAddr, tokenAddr, value);    
    }
}