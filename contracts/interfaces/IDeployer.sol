pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IDeployer {
	function getContractAddress(string calldata key) external view returns (address);
}