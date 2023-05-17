pragma solidity >=0.6.0;


interface ID8xHedgingManagerFactory {

    function getRemoteContractAddresses() external view returns (address, address);

    function create(address _poolAddr) external returns (address);
}