pragma solidity >=0.6.0;

interface IUnderlyingCreditProviderFactory {
    function create(address _udlFeedAddr) external returns (address);
}