pragma solidity >=0.6.0;

interface IProposalManager {
    enum VoteType {PROTOCOL_SETTINGS, POOL_SETTINGS, ORACLE_SETTINGS}
    enum Quorum { SIMPLE_MAJORITY, TWO_THIRDS, QUADRATIC }
    function isRegisteredProposal(address addr) external view returns (bool);
    function resolveProposal(uint id) external view returns (address);
    function resolve(address addr) external view returns (address);
    function proposalCount() external view returns (uint);
    function registerProposal(address addr, address poolAddress, Quorum quorum, VoteType voteType, uint expiresAt ) external returns (uint id, address wp);
}