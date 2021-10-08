pragma solidity >=0.6.0;

interface IProposalManager {
    function isRegisteredProposal(address addr) external view returns (bool);
    function resolve(address addr) external view returns (address);
}