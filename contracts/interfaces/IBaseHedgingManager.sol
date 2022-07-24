pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IBaseHedgingManager {
    function getHedgeExposure(address underlying) external view returns (uint);
    function idealHedgeExposure(address underlying) external view returns (uint);
    function realHedgeExposure(address underlying) external view returns (uint);
    function balanceExposure(address underlying) external returns (bool);
}