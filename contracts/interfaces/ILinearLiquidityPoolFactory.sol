pragma solidity >=0.6.0;

interface ILinearLiquidityPoolFactory {
    function create(string calldata name, string calldata symbolSuffix) external returns (address);
}