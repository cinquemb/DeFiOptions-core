pragma solidity >=0.6.0;

interface IGNSHedgingManagerFactory {
    function _referrer() external returns (address);
    function _gnsTradingAddr() external returns (address);
    function _gnsPairInfoAddr() external returns (address);
    function _gnsFarmTradingStorageAddr() external returns (address);
    function _daiAddr() external returns (address);
    function create(address _poolAddr) external returns (address);
}