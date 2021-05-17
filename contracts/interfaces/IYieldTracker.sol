pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IYieldTracker {

    function push(uint32 date, uint balance, uint value) external;
    function yield(address target, uint dt) external view returns (uint y);
}