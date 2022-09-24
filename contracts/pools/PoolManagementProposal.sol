pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../governance/Proposal.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IProtocolSettings.sol";
import "../utils/OpenZeppelinOwnable.sol";


contract PoolManagementProposal is Proposal, OpenZeppelinOwnable {

    bytes[] executionBytes;

    function setexecutionBytes(bytes[] memory _executionBytes) onlyOwner public {
        executionBytes = _executionBytes;
    }

    function getExecutionBytes() public view returns (bytes[] memory) {
        return executionBytes;
    }

    function getName() public override view returns (string memory) {

        return "Pool Management Operation";
    }

    function execute(IProtocolSettings _settings) public override {

    }

    function executePool(IERC20 pool) public override {
        
        require(executionBytes.length > 0, "no functions to call");
        for (uint i=0; i< executionBytes.length; i++) {
            (bool success, ) = address(pool).call(executionBytes[i]);
        }
    }
}