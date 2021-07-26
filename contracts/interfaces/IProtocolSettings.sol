pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProtocolSettings {
	function getCreditWithdrawlTimeLock() external view returns (uint);
    function updateCreditWithdrawlTimeLock(uint duration) external;
	function checkPoolBuyCreditTradable(address poolAddress) external view returns (bool);
	function checkPoolSellCreditTradable(address poolAddress) external view returns (bool);
	function applyCreditInterestRate(uint value, uint date) external view returns (uint);
    function getTokenRate(address token) external view returns (uint v, uint b);
    function exchangeTime() external view returns (uint256);
}