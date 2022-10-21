pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./Proposal.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IProtocolSettings.sol";
import "../utils/OpenZeppelinOwnable.sol";


contract ProtocolSettingsProposal is Proposal, OpenZeppelinOwnable {

    bytes[] executionBytes;

    function setExecutionBytes(bytes[] memory _executionBytes) onlyOwner public {
        executionBytes = _executionBytes;
    }

    function getExecutionBytes() public view returns (bytes[] memory) {
        return executionBytes;
    }

    function getExecutionBytesSize() public view returns (uint) {
        return executionBytes.length;
    }

    function getName() public override view returns (string memory) {

        return "Protocol Settings Mangement Operation";
    }

    function execute(IProtocolSettings _settings) public override {
        require(executionBytes.length > 0, "no functions to call");
        for (uint i=0; i< executionBytes.length; i++) {
            (bool success, ) = address(_settings).call(executionBytes[i]);
            require(success == true, "failed to sucessfully execute");
        }
    }

    function executePool(IERC20 pool) public override {
        
    }
}