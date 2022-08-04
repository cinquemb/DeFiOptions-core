pragma solidity >=0.6.0;

interface IUnderlyingVault {
    function liquidate(address owner, address token, address feed, uint amountOut) external returns (uint _in, uint _out);
    function release(address owner, address token, address feed, uint value) external;
}