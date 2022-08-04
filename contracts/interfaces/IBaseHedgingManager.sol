pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IBaseHedgingManager {
	function getPosSize(address underlying, address account, bool isLong) external view returns (uint[] memory);
    function getHedgeExposure(address underlying, address account) external view returns (int256);
    function idealHedgeExposure(address underlying, address account) external view returns (int256);
    function realHedgeExposure(address udlFeedAddr, address account) external view returns (int256);
    function balanceExposure(address underlying, address account) external returns (bool);
}