pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface ICreditToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function issue(address to, uint value) external;
    function balanceOf(address owner) external view returns (uint bal);
    function swapForExchangeBalance(uint value) external;
    function requestWithdraw() external;
}