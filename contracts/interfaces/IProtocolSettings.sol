pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProtocolSettings {
	function getCreditWithdrawlTimeLock() external view returns (uint);
    function updateCreditWithdrawlTimeLock(uint duration) external;
	function checkPoolBuyCreditTradable(address poolAddress) external view returns (bool);
	function checkUdlIncentiveBlacklist(address udlAddr) external view returns (bool);
	function checkDexAggIncentiveBlacklist(address dexAggAddress) external view returns (bool);
	function applyCreditInterestRate(uint value, uint date) external view returns (uint);
	function getSwapRouterInfo() external view returns (address router, address token);
	function getSwapRouterTolerance() external view returns (uint r, uint b);
	function getSwapPath(address from, address to) external view returns (address[] memory path);
    function getTokenRate(address token) external view returns (uint v, uint b);
    function getCirculatingSupply() external view returns (uint);
    function getUdlFeed(address addr) external view returns (int);
    function setUdlCollateralManager(address udlFeed, address ctlMngr) external;
    function getUdlCollateralManager(address udlFeed) external view returns (address);
    function getVolatilityPeriod() external view returns(uint);
    function getAllowedTokens() external view returns (address[] memory);
    function setDexOracleTwapPeriod(address dexOracleAddress, uint256 _twapPeriod) external;
    function getDexOracleTwapPeriod(address dexOracleAddress) external view returns (uint256);
    function exchangeTime() external view returns (uint256);
}