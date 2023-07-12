pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseRehypothecationManager.sol";
import "../interfaces/external/teller/ITellerInterface.sol";


contract TellerRehypothecationManager is BaseRehypothecationManager {

	/*

	- for short 
			- lend out user asset to teller via rehypotication manager
				- (at undercollateralized rate, ex: $100 usdc collateral for $1000 notional token loan amount? (coming from dod rehypotication)
				- dao determined max ratio's for lend for short addr?
				- dao determined apy for addr?
			- market sell asset for leveraged short?
				- would need to buy back the asset at spot market rates, payback loan
			
			- supply as liq in perp protocol and short with stables collateral?
		
		- for long
			- lend out user asset to teller via rehypotication manager
				- (at undercollateralized rate, ex: $100 notional token collateral for $1000 in dodd [coming from dod, but need to incentivze users to create liq pools of token/dodd])
				- dao determined max ratio's for lend short addr (dodd)?
				- dao determined apy for addr?

			- market buy asset for leveraged long?
				- would need to sell back the asset for stables (or dodd if at higher rate), deposit stables in dod, payback loan

	*/

	mapping(address => mapping(address => mapping(address => uint256))) lenderCommitmentIdMap;
	mapping(address => mapping(address => mapping(address => uint256))) borrowerBidIdMap;

	address tellerInterfaceAddr = address(0);
	
	function lend(address asset, address collateral, uint amount) override external {
		//TODO: only allow dao approved heging manager to call

		//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/lenders/create-commitment

		require(lenderCommitmentIdMap[msg.sender][asset][collateral] == 0, "already lending");
		//TODO: Need to transfer asset from proper place here (from udlCreditProvider for non stable, from pool credit balance for stable)
		//TODO: if non stable, first issue the udl credit to the hedging manager then transfer here, can only hedge against udl credit
		/**
		* @notice Creates a loan commitment from a lender for a market.
		* @param _commitment The new commitment data expressed as a struct
		* @param _borrowerAddressList The array of borrowers that are allowed to accept loans using this commitment
		* @return commitmentId_ returns the commitmentId for the created commitment
		*/

		ITellerInterface.Commitment memory _commitment;
		address[] memory _borrowerAddressList;
		uint256 commitmentId_ = ITellerInterface(tellerInterfaceAddr).createCommitment(
		   _commitment,
		   _borrowerAddressList
		);

		lenderCommitmentIdMap[msg.sender][asset][collateral] = commitmentId_;
	}

    function withdraw(address asset, address collateral, uint amount) override external {
    	//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/lenders/claim-collateral
    	/**
		 * @notice Withdraws deposited collateral from the created escrow of a bid that has been successfully repaid.
		 * @param _bidId The id of the bid to withdraw collateral for.
		 */
		//TODO: then transfer asset and collateral back to proper place

		require(lenderCommitmentIdMap[msg.sender][asset][collateral] > 0, "no outstanding loan");
		require(borrowerBidIdMap[msg.sender][asset][collateral] > 0, "no outstanding borrow");
		ITellerInterface(tellerInterfaceAddr).withdraw(
			borrowerBidIdMap[msg.sender][asset][collateral]
		);

		borrowerBidIdMap[msg.sender][asset][collateral] = 0;
		lenderCommitmentIdMap[msg.sender][asset][collateral] = 0;
    }

    function borrow(address asset, address collateral, uint amount) override external {
    	//TODO: only allow dao approved heging manager to call
    	//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/borrowers/accept-commitment
    	/**
		 * @notice Accept the commitment to submitBid and acceptBid using the funds
		 * @dev LoanDuration must be longer than the market payment cycle
		 * @param _commitmentId The id of the commitment being accepted.
		 * @param _principalAmount The amount of currency to borrow for the loan.
		 * @param _collateralAmount The amount of collateral to use for the loan.
		 * @param _collateralTokenId The tokenId of collateral to use for the loan if ERC721 or ERC1155.
		 * @param _collateralTokenAddress The contract address to use for the loan collateral token.s
		 * @param _interestRate The interest rate APY to use for the loan in basis points.
		 * @param _loanDuration The overall duratiion for the loan.  Must be longer than market payment cycle duration.
		 * @return bidId The ID of the loan that was created on TellerV2
		 */
		require(lenderCommitmentIdMap[msg.sender][asset][collateral] > 0, "no outstanding loan");
		require(borrowerBidIdMap[msg.sender][asset][collateral] == 0, "already borrowing");
		//TODO: Need to transfer collateral from proper place here

		uint256 _principalAmount;
	    uint256 _collateralAmount;
	    uint256 _collateralTokenId = 0;//0 for erc20's
	    uint16 _interestRate;
	    uint32 _loanDuration;

		uint256 _bidId = ITellerInterface(tellerInterfaceAddr).acceptCommitment(
		    lenderCommitmentIdMap[msg.sender][asset][collateral],
		    _principalAmount,
		    _collateralAmount,
		    _collateralTokenId,//0 for erc20's
		    collateral,
		    _interestRate, 
		    _loanDuration
		);

		borrowerBidIdMap[msg.sender][asset][collateral] = _bidId;

    }
    
    function repay(address asset, address collateral, uint amount)  override external {
    	//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/borrowers/repay-loan
    	//TODO: need to transfer asset to repay here, then transfer asset and collateral back to proper place
    	/**
		 * @notice Function for users to repay an active loan in full.
		 * @param _bidId The id of the loan to make the payment towards.
		 */

		require(lenderCommitmentIdMap[msg.sender][asset][collateral] > 0, "no outstanding loan");
		require(borrowerBidIdMap[msg.sender][asset][collateral] > 0, "no outstanding borrow");

		ITellerInterface(tellerInterfaceAddr).repayLoanFull(borrowerBidIdMap[msg.sender][asset][collateral]);

		/**
		* @notice Withdraws deposited collateral from the created escrow of a bid that has been successfully repaid.
		* @param _bidId The id of the bid to withdraw collateral for.
		*/
		ITellerInterface(tellerInterfaceAddr).withdraw(borrowerBidIdMap[msg.sender][asset][collateral]);


		borrowerBidIdMap[msg.sender][asset][collateral] = 0;
		lenderCommitmentIdMap[msg.sender][asset][collateral] = 0;
    }
    
    function transferTokensToCreditProvider(address tokenAddr) override external {
        //this needs to be used if/when liquidations happen and tokens sent from external contracts end up here
        uint value = IERC20_2(tokenAddr).balanceOf(address(this));
        if (value > 0) {
            IERC20_2(tokenAddr).safeTransfer(address(creditProvider), value);
        }
    }

    function transferTokensToVault(address tokenAddr) override external {
    	//TODO: this needs to be used if/when liquidations happen and tokens sent from external contracts end up here
    	//TODO: this needs to send to the proper undelryingCreditProvider addr
        uint value = IERC20_2(tokenAddr).balanceOf(address(this));
        if (value > 0) {
            IERC20_2(tokenAddr).safeTransfer(address(vault), value);
        }
    }
}