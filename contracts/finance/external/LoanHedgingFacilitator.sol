pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../interfaces/external/teller/ITellerInterface.sol";
import "../../interfaces/IGovernableLiquidityPool.sol";
import "../../utils/Convert.sol";
import "../../utils/MoreMath.sol";
import "../../utils/SafeERC20.sol";

/*

- borrower requests loan from loanhedgingfacilitator (how much of lending asset used to hedge defined here)
	 		- loan request (1 tx)
	 			- signals loanhedgingfacilitator contract it wants to hedge

	 		- dod ui lists active loanhedgingfacilitator requests
 			
 			- traders price options, triggers loanhedgingfacilitator contract to buy it
	 				- 24 hours to submit, option string and pool address to loanhedgingfacilitator contract for particular borrower request
	 					- lender can accept bids at any time within the time window
	 					- borrower can trigger acceptance after 24h window
	 						- selects cheapest options
	 					- use exchange balance if available
	 						- if so, send cost of hedging loan back to lender
	 						- if not, use stablecoins used originate loan

	 					- borrower can also ask to hedge upside exposure to collateral?

 			- 1 tx:
	 			- loan origination happens, loan duration starts from here
	 			- lending asset needs to be sent to loanhedgingfacilitator contract
	 			- makes market buy order put options  to hedge their deposited collateral for given size
	 			- borrower gets lending asset amount - cost of hedging

*/

contract LoanHedgingFacilitator {
	using SafeERC20 for IERC20_2;
    using SafeMath for uint;
    using SignedSafeMath for int;

	struct request {
		uint256 id;
		uint256 commitmentId;
		uint256 borrowerBidId;
		uint256 startTime;
		bool active;
		bool initiated;
		bool isUpsideHedging;
		mapping(address => string) put;
		mapping(address => string) call;
		address[] putBids;
		address[] callBids;
		uint256 selectedPut;
		uint256 selectedCall;
		address selectedPutPool;
		address selectedCallPool;
		string selectedSymbol;
		address collateral;
		address principal;
		uint256 collateralAmount;
		uint256 principalAmount;
		uint16 interestRate;
		uint32 loanDuration;
		uint256 maxPrincipalHaircut;//bps
		address borrower;
		address lender;
	}
	uint256 constant MAX_AUCTION_DURATION = 60 * 60 * 24;
	uint256 constant UINT256_MAX = 2**256-1;
	mapping(uint256 => request) borrowRequest;
	uint256 borrowRequestId;
	address tellerInterfaceAddr = address(0);

	//TODO: need to check that some how bid strike is ATM?

	constructor(address _teller) public {
		tellerInterfaceAddr = _teller;
	}

	
	function requestLoan(uint256 commitmentId, address collateral, uint256 maxPrincipalHaircut, uint256 collateralAmount, uint256 principalAmount, uint16 interestRate, uint32 loanDuration, bool hedgeCollateralUpside) external {

		IERC20_2(collateral).safeTransferFrom(msg.sender, address(this), collateralAmount);

		ITellerInterface.CommitmentV2 memory commitment = ITellerInterface(tellerInterfaceAddr).commitments(commitmentId);

		borrowRequest[borrowRequestId].id = borrowRequestId;
		borrowRequest[borrowRequestId].commitmentId = commitmentId;
		borrowRequest[borrowRequestId].startTime = block.timestamp;
		borrowRequest[borrowRequestId].active = true;
		borrowRequest[borrowRequestId].initiated = true;
		borrowRequest[borrowRequestId].isUpsideHedging = hedgeCollateralUpside;
		borrowRequest[borrowRequestId].collateral = collateral;
		borrowRequest[borrowRequestId].principal = commitment.principalTokenAddress;
		borrowRequest[borrowRequestId].maxPrincipalHaircut = maxPrincipalHaircut;
		borrowRequest[borrowRequestId].collateralAmount = collateralAmount;
		borrowRequest[borrowRequestId].principalAmount = principalAmount;
		borrowRequest[borrowRequestId].interestRate = interestRate;
		borrowRequest[borrowRequestId].loanDuration = loanDuration;
		borrowRequest[borrowRequestId].borrower = msg.sender;
		borrowRequest[borrowRequestId].lender = commitment.lender;

		borrowRequestId++;

	}

	function submitOptionBid(uint256 borrowId, address liquidityPool, string calldata lenderOptionSymbol, string calldata borrowerOptionSymbol) external {
		/*
			each bid gets bid id for loan auction, close auction if beyond time, check if msg.sender is holding at least greater than 50% of pool tokens
		*/

		uint256 ownershipBal = IERC20_2(liquidityPool).balanceOf(msg.sender);
		uint256 tSupply = IERC20_2(liquidityPool).totalSupply();

		require(ownershipBal.mul(2) > tSupply, "not enough control");
		require(block.timestamp.sub(borrowRequest[borrowId].startTime) < MAX_AUCTION_DURATION, "auction closed");

		borrowRequest[borrowId].put[liquidityPool] = lenderOptionSymbol;

		if (borrowRequest[borrowId].isUpsideHedging == true) {
			if (compareStrings(borrowerOptionSymbol, "") == false) {
				borrowRequest[borrowId].call[liquidityPool] = borrowerOptionSymbol;
			}
		}
	}

	function acceptBestOptionBids(uint256 borrowId) external {
		/*
			- 1 tx:
	 			- loan origination happens, loan duration starts from here
	 			- lending asset needs to be sent to loanhedgingfacilitator contract
	 			- makes market buy order put options  to hedge their deposited collateral for given size
	 			- borrower gets lending asset amount - cost of hedging

		*/

		//contract borrows on behalf of user

		require((borrowRequest[borrowId].active == true) && (msg.sender == borrowRequest[borrowId].lender || borrowRequest[borrowId].startTime.add(MAX_AUCTION_DURATION) > block.timestamp), "cannot close auction");

		borrowRequest[borrowId].active = false;

		uint256 _bidId = ITellerInterface(tellerInterfaceAddr).acceptCommitment(
		    borrowRequest[borrowId].commitmentId,
		    borrowRequest[borrowId].principalAmount,
		    borrowRequest[borrowId].collateralAmount,
		    0,//0 for erc20's
		    borrowRequest[borrowId].collateral,
		    borrowRequest[borrowId].interestRate, 
		    borrowRequest[borrowId].loanDuration
		);

		borrowRequest[borrowId].borrowerBidId = _bidId;

		(int256 callBidId, int256 putBidId, address callBidAddr, address putBidAddr) = selectBestBid(borrowId);
		//_price.mul(oEx.vol).div(_volumeBase) == exchange balance cost

		require(putBidId > -1, "no put bids");
		borrowRequest[borrowId].selectedPutPool = putBidAddr;
		borrowRequest[borrowId].selectedCallPool = callBidAddr;
		borrowRequest[borrowId].selectedSymbol = borrowRequest[borrowId].put[putBidAddr];

		executeHedgeAndLoan(borrowId, putBidAddr, callBidAddr, callBidId, putBidId);
	}

	function repayLoanFull(uint256 borrowId) external {
		IERC20_2(borrowRequest[borrowId].principal).safeTransferFrom(msg.sender, address(this), borrowRequest[borrowId].principalAmount);
		ITellerInterface(tellerInterfaceAddr).repayLoanFull(borrowRequest[borrowId].borrowerBidId);
		ITellerInterface(tellerInterfaceAddr).withdraw(borrowRequest[borrowId].borrowerBidId);
		IERC20_2(borrowRequest[borrowId].collateral).transfer(msg.sender, borrowRequest[borrowId].collateralAmount);

	}

	function selectBestBid(uint256 borrowId) public view returns (int256 callBidId, int256 putBidId, address callBidAddr, address putBidAddr){

		uint i;
		putBidId = -1;
		callBidId = -1;
		uint256 bestPrice = UINT256_MAX;
		IGovernableLiquidityPool pool;

		for(i=0;i<borrowRequest[borrowId].putBids.length;i++){
			pool = IGovernableLiquidityPool(borrowRequest[borrowId].putBids[i]);
			try pool.queryBuy(borrowRequest[borrowId].put[borrowRequest[borrowId].putBids[i]], true) returns (uint _buyPrice, uint) {
				if (_buyPrice < bestPrice) {
	            	bestPrice = _buyPrice;
	            	putBidAddr = borrowRequest[borrowId].putBids[i];
	            	putBidId = int256(i);
				}
	        } catch (bytes memory /*lowLevelData*/) {
	        	continue;
	        }
		}


		if (borrowRequest[borrowId].isUpsideHedging == true) {
			bestPrice = UINT256_MAX;
	        for(i=0;i<borrowRequest[borrowId].callBids.length;i++){
				pool = IGovernableLiquidityPool(borrowRequest[borrowId].callBids[i]);
				try pool.queryBuy(borrowRequest[borrowId].call[borrowRequest[borrowId].callBids[i]], true) returns (uint _buyPrice, uint) {
					if (_buyPrice < bestPrice) {
		            	bestPrice = _buyPrice;
		            	callBidAddr = borrowRequest[borrowId].callBids[i];
		            	callBidId = int256(i);
					}
		        } catch (bytes memory /*lowLevelData*/) {
		            continue;
		        }
			}		
		}
	}

	function compareStrings(string memory a, string memory b) private pure returns (bool) {
	    return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
	}

	function executeHedgeAndLoan(uint256 borrowId, address putBidAddr, address callBidAddr, int256 callBidId, int256 putBidId) private {
		uint256 totalHedgeCost = 0;

		uint256 optVolume = Convert.to18DecimalsBase(
			borrowRequest[borrowId].collateral,
			borrowRequest[borrowId].collateralAmount
		);

		totalHedgeCost = downsideHedge(totalHedgeCost, borrowId, putBidAddr, putBidId, optVolume);

		if (borrowRequest[borrowId].isUpsideHedging == true) {
			require(callBidId > -1, "no call bids");
			totalHedgeCost = upsideHedge(totalHedgeCost, borrowId, callBidAddr, callBidId, optVolume);
		}		

		uint residual = borrowRequest[borrowId].principalAmount.sub(totalHedgeCost);
		uint maxHedgeCost = borrowRequest[borrowId].principalAmount.mul(borrowRequest[borrowRequestId].maxPrincipalHaircut).div(10000);
		require(totalHedgeCost <= maxHedgeCost, "outside maxPrincipalHaircut");
		//send residual principal to borrower
		IERC20_2(borrowRequest[borrowId].principal).transfer(borrowRequest[borrowId].borrower, residual);
	}

	function upsideHedge(uint256 totalHedgeCost, uint256 borrowId, address callBidAddr, int256 callBidId, uint256 optVolume) private returns (uint256) {
		require(callBidId > -1, "no call bids");
		(borrowRequest[borrowId].selectedCall,) = IGovernableLiquidityPool(callBidAddr).queryBuy(borrowRequest[borrowId].call[callBidAddr], true);
		uint256 cHedgeCost = Convert.from18DecimalsBase(borrowRequest[borrowId].principal, borrowRequest[borrowId].selectedCall.mul(optVolume).div(1e18));
		
		IERC20_2 pTk = IERC20_2(borrowRequest[borrowId].principal);
		if (pTk.allowance(address(this), callBidAddr) > 0) {
            pTk.safeApprove(callBidAddr, 0);
        }
        pTk.safeApprove(callBidAddr, cHedgeCost);

		address optCallTkn = IGovernableLiquidityPool(callBidAddr).buy(
			borrowRequest[borrowId].call[callBidAddr],
			borrowRequest[borrowId].selectedCall,
			optVolume, 
			borrowRequest[borrowId].principal //address token
		);
		//transfer upside protection to borrower
		IERC20_2(optCallTkn).transfer(borrowRequest[borrowId].borrower, optVolume);
		totalHedgeCost += cHedgeCost;
		return totalHedgeCost;
	}

	function downsideHedge(uint256 totalHedgeCost, uint256 borrowId, address putBidAddr, int256 putBidId, uint256 optVolume) private returns (uint256) {
		(borrowRequest[borrowId].selectedPut,) = IGovernableLiquidityPool(putBidAddr).queryBuy(borrowRequest[borrowId].put[putBidAddr], true);
		uint256 pHedgeCost = Convert.from18DecimalsBase(borrowRequest[borrowId].principal, borrowRequest[borrowId].selectedPut.mul(optVolume).div(1e18));

		IERC20_2 pTk = IERC20_2(borrowRequest[borrowId].principal);
		if (pTk.allowance(address(this), putBidAddr) > 0) {
            pTk.safeApprove(putBidAddr, 0);
        }
        pTk.safeApprove(putBidAddr, pHedgeCost);

		address optPutTkn = IGovernableLiquidityPool(putBidAddr).buy(
			borrowRequest[borrowId].put[putBidAddr],
			borrowRequest[borrowId].selectedPut,
			optVolume, 
			borrowRequest[borrowId].principal //address token
		);
		//transfer downside protection to lender
		IERC20_2(optPutTkn).transfer(borrowRequest[borrowId].lender, optVolume);
		
		totalHedgeCost += pHedgeCost;
		return totalHedgeCost;
	}
}