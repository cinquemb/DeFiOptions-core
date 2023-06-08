pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseRehypothecationManager.sol";

contract TellerRehypothecationManager is BaseRehypothecationManager {
	
	function lend(address asset, address collateral, uint amount) override external {

		//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/lenders/create-commitment

		/**
		* @notice Creates a loan commitment from a lender for a market.
		* @param _commitment The new commitment data expressed as a struct
		* @param _borrowerAddressList The array of borrowers that are allowed to accept loans using this commitment
		* @return commitmentId_ returns the commitmentId for the created commitment
		*/
		function createCommitment(
		   Commitment calldata _commitment,
		   address[] calldata _borrowerAddressList
		) public returns (uint256 commitmentId_);


	}

    function withdraw(address asset, uint amount) override external {
    	//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/lenders/claim-collateral
    	/**
		 * @notice Withdraws deposited collateral from the created escrow of a bid that has been successfully repaid.
		 * @param _bidId The id of the bid to withdraw collateral for.
		 */
		function withdraw(uint256 _bidId)

    }

    function borrow(address asset, address collateral, uint amount) override external {
    	//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/borrowers/accept-commitment
    	//TODO: NEED TO KEEP TRACK OF BID ID FOR REPAY/WITHDRAW
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
		function acceptCommitment(
		    uint256 _commitmentId,
		    uint256 _principalAmount,
		    uint256 _collateralAmount,
		    uint256 _collateralTokenId,
		    address _collateralTokenAddress,
		    uint16 _interestRate, 
		    uint32 _loanDuration
		)

    }
    function repay(address collateral, uint amount)  override external {
    	//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/borrowers/repay-loan
    	/**
		 * @notice Function for users to repay an active loan in full.
		 * @param _bidId The id of the loan to make the payment towards.
		 */
		function repayLoanFull(uint256 _bidId);

		/**
		* @notice Withdraws deposited collateral from the created escrow of a bid that has been successfully repaid.
		* @param _bidId The id of the bid to withdraw collateral for.
		*/
		function withdraw(uint256 _bidId);
    }
    
    function transferTokensToCreditProvider(address tokenAddr) override external {
        //this needs to be used if/when liquidations happen and tokens sent from external contracts end up here
        uint value = IERC20_2(tokenAddr).balanceOf(address(this));
        if (value > 0) {
            IERC20_2(tokenAddr).safeTransfer(address(creditProvider), value);
        }
    }

    function transferTokensToVault(address tokenAddr) override external {
    	//this needs to be used if/when liquidations happen and tokens sent from external contracts end up here
        uint value = IERC20_2(tokenAddr).balanceOf(address(this));
        if (value > 0) {
            IERC20_2(tokenAddr).safeTransfer(address(vault), value);
        }
    }
}