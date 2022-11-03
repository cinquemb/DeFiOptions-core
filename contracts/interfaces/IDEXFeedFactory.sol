pragma solidity >=0.6.0;

interface IDEXFeedFactory {
    function create(address underlying, address stable, address dexTokenPair) external returns (address);
}