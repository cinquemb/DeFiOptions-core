pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProposalWrapper {
    enum VoteType {PROTOCOL_SETTINGS, POOL_SETTINGS, ORACLE_SETTINGS}
    enum Status { PENDING, OPEN, APPROVED, REJECTED }
    function isPoolSettingsAllowed() external view returns (bool);
    function getStatus() external view returns (Status);
    function getVoteType() external view returns (VoteType);
    function getGovernanceToken() external view returns (address);
    function isActive() external view returns (bool);
}