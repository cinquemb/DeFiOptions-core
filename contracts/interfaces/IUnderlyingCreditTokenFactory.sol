pragma solidity >=0.6.0;

interface IUnderlyingCreditTokenFactory {
    function create(address _udlFeedAddr) external returns (address);
}