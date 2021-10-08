pragma solidity >=0.6.0;

interface IGovToken {
    function totalSupply() external view returns (uint256);
    function enforceHotVotingSetting() external view;
    function isRegisteredProposal(address addr) external view returns (bool);
    function calcShare(address owner, uint base) external view returns (uint);
    function delegateBalanceOf(address delegate) external view returns (uint);
}