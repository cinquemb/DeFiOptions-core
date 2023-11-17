pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

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
	struct request {
		uint256 id;
		uint256 commitmentId;
		bool active;
		bool isUpsideHedging;
		mapping(address => string) put;
		mapping(address => string) call;
		uint256 selectedPut;
		uint256 selectedCall;
		address selectedPool;
		string selectedSymbol;

	}
	mapping(uint256 => request) borrowRequest;
	uint256 borrowRequestId;
	
	function requestLoan(uint256 commitmentId, address collateral, uint256 collateralAmount, bool hedgeCollateralUpside){
		/*
			makes loan request, starts auction, marks as active, sends collateral to here
		*/
	}

	function submitOptionBid(uint256 borrowId, address liquidityPool, string lenderOptionSymbol, string borrowerOptionSymbol) {
		/*
			each bid gets bid id for loan auction, close auction if beyond time
		*/
	}

	function acceptOptionBid(uint256 borrowId, uint256 bidId) {
		/*
			- 1 tx:
	 			- loan origination happens, loan duration starts from here
	 			- lending asset needs to be sent to loanhedgingfacilitator contract
	 			- makes market buy order put options  to hedge their deposited collateral for given size
	 			- borrower gets lending asset amount - cost of hedging

		*/
	}

	function selectBestBid(uint256 loanId, uint256 bidId)

}