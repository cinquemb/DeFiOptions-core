pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IGFarmTradingStorageV5 {
    struct Trade {
        address trader;
        uint pairIndex;
        uint index;
        uint initialPosToken;       // 1e18
        uint positionSizeDai;       // 1e18
        uint openPrice;             // PRECISION
        bool buy;
        uint leverage;
        uint tp;                    // PRECISION
        uint sl;                    // PRECISION
    }
    struct TradeInfo {
        uint tokenId;
        uint tokenPriceDai;         // PRECISION
        uint openInterestDai;       // 1e18
        uint tpLastUpdated;
        uint slLastUpdated;
        bool beingMarketClosed;
    }

    // Trades mappings
    //mapping(address => mapping(uint => mapping(uint => Trade))) public openTrades;
    //mapping(address => mapping(uint => mapping(uint => TradeInfo))) public openTradesInfo;
    //mapping(address => mapping(uint => uint)) public openTradesCount;

    function openTrades(address, uint, uint) external view returns (Trade memory);
    function openTradesInfo(address, uint, uint) external view returns (TradeInfo memory);
    function openTradesCount(address, uint) external view returns (uint);

}