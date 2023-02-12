pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./PoolManagementProposal.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/IProposalManager.sol";
import "../interfaces/IProposalWrapper.sol";
import "../utils/SafeERC20.sol";

contract FastPoolManagement {
	using SafeERC20 for IERC20_2;
	using SafeMath for uint256;

	struct FPMLimitOrder {
		address stableToken;
		uint256 stableTokenValue;
		bool isDeposit;
		address proposalManagerAddr;
		bytes _code;
		bytes[] _executionBytes;
		IProposalManager.Quorum quorum;
		IProposalManager.VoteType voteType;
		uint expiresAt;
		address optionsExchangeAddr;
		bytes[] _executionCreateOptionsBytes;
	}

	function deployProposeVoteExecute(
		address proposalManagerAddr,
		bytes memory _code,
		bytes[] memory _executionBytes,
		address poolAddress,
		IProposalManager.Quorum quorum,
		IProposalManager.VoteType voteType,
		uint expiresAt,
		bool isExecuteVote
	) public returns (address) {
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

        return proposalWrapperAddr;
    }

    function bulkRegisterSymbols(
     	address optionsExchangeAddr,
		bytes[] memory _executionBytes
	) public {
		for (uint i=0; i< _executionBytes.length; i++) {
            (bool success, ) = optionsExchangeAddr.call(_executionBytes[i]);
        }
	}

	function createSyntheticLimitOrder(
		FPMLimitOrder memory fpmOrder
	) public returns (address) {
		/*
			NOTE: MAY NOT WORK BECAUSE IT MAY USE TOO MUCH GAS
				- POOL CREATION == HIGH GAS
				- OPTION SYMBOL REGISTRATION == HIGH GAS
				- PROPOSAL == HIGH GAS?
			PROCESS:
				- create pool (if pool does not exist for user)
					- how to name params? default to addrs used for interaction?
				- deposit collateral?
					- approve fpm contract
						- only needs to be done once for every new fpm deployment
					- send stabls to fpm
					- send stables to pool from fpm
					-fpm sends llp to msg.sender
				- bulkRegisterSymbols
				- deployProposeVoteExecute
					- if deposit, then no extra gov tx's needed
		*/

		bool isExecuteVote = false;
		uint256 llpValueToTransfer = 0;
		address poolAddr;
		string memory poolName = toAsciiString(msg.sender);
		poolAddr = IOptionsExchange(fpmOrder.optionsExchangeAddr).getPoolAddress(poolName);

		if (poolAddr == address(0)) {
			poolAddr = IOptionsExchange(fpmOrder.optionsExchangeAddr).createPool(poolName, poolName);
		}

		// deposit collateral?
		if(fpmOrder.isDeposit == true) {
			llpValueToTransfer = processDeposit(poolAddr, fpmOrder.stableToken, fpmOrder.stableTokenValue);
			isExecuteVote = true;
		}

		//register option symbols
		bulkRegisterSymbols(fpmOrder.optionsExchangeAddr, fpmOrder._executionCreateOptionsBytes);

		//create pool proposal
		address proposalWrapperAddr = deployProposeVoteExecute(
			fpmOrder.proposalManagerAddr,
			fpmOrder._code,
			fpmOrder._executionBytes,
			poolAddr,
			fpmOrder.quorum,
			fpmOrder.voteType,
			fpmOrder.expiresAt,
			isExecuteVote
		);

		// if vote was excuted, transfer llp tokens to msg.sender
		if (isExecuteVote == true) {
			IERC20_2(poolAddr).transfer(msg.sender, llpValueToTransfer);
		}

		return proposalWrapperAddr;
	}

	function processDeposit(address poolAddr, address stableToken, uint256 stableTokenValue) private returns (uint256) {
		IERC20_2(stableToken).safeTransferFrom(msg.sender, address(this), stableTokenValue);
    	IERC20_2(stableToken).safeApprove(address(poolAddr), stableTokenValue);
		
		// send stables to pool from fpm, fpm recives llp
		//NOTE: IF FPM gets LLP, then FPM can auto close proposal
		uint256 balBefore = IERC20_2(poolAddr).balanceOf(address(this));
		IGovernableLiquidityPool(poolAddr).depositTokens(address(this), stableToken, stableTokenValue);
		uint256 balAfter = IERC20_2(poolAddr).balanceOf(address(this));
		uint256 llpValueToTransfer = balAfter.sub(balBefore);

		return llpValueToTransfer;
	}

	function toAsciiString(address x) internal pure returns (string memory) {
    bytes memory s = new bytes(40);
	    for (uint i = 0; i < 20; i++) {
	        bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
	        bytes1 hi = bytes1(uint8(b) / 16);
	        bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
	        s[2*i] = char(hi);
	        s[2*i+1] = char(lo);            
	    }
	    return string(s);
	}

	function char(bytes1 b) internal pure returns (bytes1 c) {
	    if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
	    else return bytes1(uint8(b) + 0x57);
	}
}