pragma solidity >=0.6.0;

interface IProposalManager {
    function isRegisteredProposal(address addr) external view returns (bool);
    function resolveProposal(uint id) external view returns (address);
    function resolve(address addr) external view returns (address);
    function proposalCount() external view returns (uint);
}