pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IBaseHedgingManager {
    function getHedgeExposure(address underlying, address account) external view returns (uint);
    function idealHedgeExposure(address underlying, address account) external view returns (uint);
    function realHedgeExposure(address udlFeedAddr, address account) external view returns (uint);
    function balanceExposure(address underlying, address account) external returns (bool);
}