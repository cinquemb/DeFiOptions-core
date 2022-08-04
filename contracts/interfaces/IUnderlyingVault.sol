pragma solidity >=0.6.0;

interface IUnderlyingVault {
    function balanceOf(address owner, address token) external view returns (uint);
    function liquidate(address owner, address token, address feed, uint amountOut) external returns (uint _in, uint _out);
    function release(address owner, address token, address feed, uint value) external;
    function lock(address owner, address token, uint value) external;
}