pragma solidity >=0.6.0;

interface IGovToken {
    function totalSupply() external view returns (uint256);
    function isRegisteredProposal(address addr) external view returns (bool);
}