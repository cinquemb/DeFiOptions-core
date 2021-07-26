pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProposal {
    function open(uint _id) external;
    function getId() external view returns (uint);
    function isPoolSettingsAllowed() external view returns (bool);
    function isOracleSettingsAllowed() external view returns (bool);
    function isProtocolSettingsAllowed() external view returns (bool);
}