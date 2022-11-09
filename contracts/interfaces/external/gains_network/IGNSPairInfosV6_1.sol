pragma solidity >=0.6.0;

interface IGNSPairInfosV6_1 {
    // Dynamic price impact value on trade opening
    function getTradePriceImpact(
        uint openPrice,        // PRECISION
        uint pairIndex,
        bool long,
        uint tradeOpenInterest // 1e18 (DAI)
    ) external view returns(
        uint priceImpactP,     // PRECISION (%)
        uint priceAfterImpact  // PRECISION
    );
}