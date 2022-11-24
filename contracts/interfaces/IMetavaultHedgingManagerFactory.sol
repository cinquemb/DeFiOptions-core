pragma solidity >=0.6.0;


interface IMetavaultHedgingManagerFactory {

    function getRemoteContractAddresses() external view returns (address, address, bytes32);

    function create(address _poolAddr) external returns (address);
}