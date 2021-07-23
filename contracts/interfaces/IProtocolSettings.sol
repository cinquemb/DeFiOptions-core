pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProtocolSettings {
	function checkPoolBuyCreditTradable(address poolAddress) external view returns (bool);
	function checkPoolSellCreditTradable(address poolAddress) external view returns (bool);
    function getTokenRate(address token) external view returns (uint v, uint b);
    function exchangeTime() external view returns (uint256);
}