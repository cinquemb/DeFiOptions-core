pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IUnderlyingCreditToken {
    function initialize(address _udlCdp) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function getUdlAsset() external view returns (address);
    function issue(address to, uint value) external;
    function balanceOf(address owner) external view returns (uint bal);
    function requestWithdraw() external;
}