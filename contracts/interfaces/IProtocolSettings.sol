pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProtocolSettings {
	function getCreditWithdrawlTimeLock() external view returns (uint);
    function updateCreditWithdrawlTimeLock(uint duration) external;
	function checkPoolBuyCreditTradable(address poolAddress) external view returns (bool);
	function checkPoolSellCreditTradable(address poolAddress) external view returns (bool);
	function checkUdlIncentiveBlacklist(address udlAddr) external view returns (bool);
	function checkDexAggIncentiveBlacklist(address dexAggAddress) external view returns (bool);
	function applyCreditInterestRate(uint value, uint date) external view returns (uint);
    function getTokenRate(address token) external view returns (uint v, uint b);
    function getUdlFeed(address addr) external view returns (int);
    function getVolatilityPeriod() external view returns(uint);
    function getAllowedTokens() external view returns (address[] memory);
    function exchangeTime() external view returns (uint256);
}