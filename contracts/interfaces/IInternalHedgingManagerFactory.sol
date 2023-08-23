pragma solidity >=0.6.0;


interface IInternalHedgingManagerFactory {

    function getRemoteContractAddresses() external view returns (address);

    function create(address _poolAddr) external returns (address);
}