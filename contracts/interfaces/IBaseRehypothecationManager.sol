pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IBaseRehypothecationManager {
	function notionalExposure(address account, address asset, address collateral) external view returns (uint256);
	function borrowExposure(address account, address asset, address collateral) external view returns (uint256);
	function lend(address asset, address collateral, uint assetAmount, uint collateralAmount, address udlFeed) external;
	function withdraw(address asset, address collateral, uint amount) external;
	function borrow(address asset, address collateral, uint assetAmount, uint collateralAmount, address udlFeed) external;
	function repay(address asset, address collateral, address udlFeed) external;
	function transferTokensToCreditProvider(address tokenAddr) external;
    function transferTokensToVault(address tokenAddr) external;
}