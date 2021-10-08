pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProposalWrapper {
    function isPoolSettingsAllowed() external view returns (bool);
}