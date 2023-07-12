pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IBaseRehypothecationManager {
	function lend(address asset, address collateral, uint amount) external;
	function withdraw(address asset, address collateral, uint amount) external;
	function borrow(address asset, address collateral, uint amount) external;
	function repay(address asset, address collateral, uint amount) external;
	function transferTokensToCreditProvider(address tokenAddr) external;
    function transferTokensToVault(address tokenAddr) virtual external;
}