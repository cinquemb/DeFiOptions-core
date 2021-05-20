pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface ICreditProvider {
    function addBalance(address to, address token, uint value) external;
}