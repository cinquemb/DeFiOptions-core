pragma solidity >=0.6.0;

interface IUnderlyingCreditTokenFactory {
    function create(address _poolAddr) external returns (address);
}