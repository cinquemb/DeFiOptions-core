pragma solidity >=0.6.0;

interface UnderlyingFeed {

    function symbol() external view returns (string memory);

    function getUnderlyingAddr() external view returns (address);

    function getPrivledgedPublisherKeeper() external view returns (address);

    function getUnderlyingAggAddr() external view returns (address);

    function getLatestPrice() external view returns (uint timestamp, int price);

    function getPrice(uint position) external view returns (uint timestamp, int price);

    function getDailyVolatility(uint timespan) external view returns (uint vol);

    function getDailyVolatilityCached(uint timespan) external view returns (uint vol, bool cached);

    function calcLowerVolatility(uint vol) external view returns (uint lowerVol);

    function calcUpperVolatility(uint vol) external view returns (uint upperVol);

    function prefetchSample() external;

    function prefetchDailyPrice(uint roundId) external;

    function prefetchDailyVolatility(uint timespan) external;
}