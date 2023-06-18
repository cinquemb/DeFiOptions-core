pragma solidity >=0.6.0;

interface IUnderlyingCreditProviderFactory {
    function create(address _poolAddr) external returns (address);
}