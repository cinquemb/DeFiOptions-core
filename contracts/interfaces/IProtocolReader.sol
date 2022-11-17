pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProtocolReader {
    function listPoolsData() external view returns (string[] memory, address[] memory);
}