pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./PoolManagementProposal.sol";
import "../interfaces/IProposalManager.sol";
import "../interfaces/IProposalWrapper.sol";

contract FastPoolManagement {
	function deployProposeVoteExecute(
		address proposalManagerAddr,
		bytes calldata _code,
		bytes[] calldata _executionBytes,
		address poolAddress,
		IProposalManager.Quorum quorum,
		IProposalManager.VoteType voteType,
		uint expiresAt,
		bool isExecuteVote
	) external {
		address pmpAddr;
		bytes memory _pmpBytes = _code;
		//deploy proposal manager
        assembly {
            // create(v, p, n)
            // v = amount of ETH to send
            // p = pointer in memory to start of code
            // n = size of code
            pmpAddr := create(callvalue(), add(_pmpBytes, 0x20), mload(_pmpBytes))       
        }
        // return address 0 on error
        require(pmpAddr != address(0), "proposasl failed init");

        //initialize proposal manager with propsoal data
        PoolManagementProposal(pmpAddr).setExecutionBytes(_executionBytes);

        //registered proposal
        (uint pid, address proposalWrapperAddr) = IProposalManager(proposalManagerAddr).registerProposal(
	        pmpAddr,
	        poolAddress,
	        quorum,
	       	voteType,
	        expiresAt
        );

        //TODO: DOES NOT WORK IF TOKENS HAVE NOT BEEN TRANSFERED TO THIS CONTRACT, MAY NEED TO HAVE A WAY TO DELEGATE FOR POOL VOTES?
        if (isExecuteVote) {
        	//vote on proposal
	        IProposalWrapper(proposalWrapperAddr).castVote(true);

	        //close proposal
	        IProposalWrapper(proposalWrapperAddr).close();
        }
     }
}