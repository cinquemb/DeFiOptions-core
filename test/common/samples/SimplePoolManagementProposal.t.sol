pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "../../../contracts/governance/Proposal.sol";
import "../../../contracts/interfaces/IProposalWrapper.sol";
import "../../../contracts/interfaces/IProtocolSettings.sol";
import "../../../contracts/interfaces/IERC20.sol";
import "../../../contracts/utils/OpenZeppelinOwnable.sol";


contract SimplePoolManagementProposal is Proposal, OpenZeppelinOwnable {

    bytes executionBytes;

    function setExecutionBytes(bytes memory _executionBytes) onlyOwner public {
        executionBytes = _executionBytes;
    }

    function getExecutionBytes() public view returns (bytes memory) {
        return executionBytes;
    }

    function getExecutionBytesSize() public view returns (uint) {
        return executionBytes.length;
    }

    function getName() public override view returns (string memory) {

        return "Pool Management Operation";
    }

    function execute(IProtocolSettings _settings) public override {

    }

    function executePool(IERC20 pool) public override {
        (bool success, ) = address(pool).call(executionBytes);
        require(success == true, "failed to sucessfully execute");
    }
}