pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IBaseHedgingManager {
	function getPosSize(address underlying, bool isLong) external view returns (uint[] memory);
    function getHedgeExposure(address underlying) external view returns (int256);
    function idealHedgeExposure(address underlying) external view returns (int256);
    function realHedgeExposure(address udlFeedAddr) external view returns (int256);
    function balanceExposure(address underlying) external returns (bool);
    function totalTokenStock() external view returns (uint v);
    function transferTokensToCreditProvider(address tokenAddr) external;

}