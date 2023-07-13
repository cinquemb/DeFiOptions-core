pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseRehypothecationManager.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/IUnderlyingCreditToken.sol";
import "../interfaces/IUnderlyingCreditProvider.sol";
import "../interfaces/external/teller/ITellerInterface.sol";

contract TellerRehypothecationManager is BaseRehypothecationManager {

	mapping(address => mapping(address => mapping(address => uint256))) lenderCommitmentIdMap;
	mapping(address => mapping(address => mapping(address => uint256))) borrowerBidIdMap;

	address tellerInterfaceAddr = address(0);

	/*
		TODO: if non stable lending (lev short), can only hedge against udl credit (collateral == exchange balance, asset == udl credit)
			- when repaying 
				- swap exchange balance for udl credit borrowed at oracle rate interally with agaisnt rehypo manager
					- hedging manager sends exchange balance to rehypo manager
					- repay loan with udl credit recieved
						- free exchanage balance collateral
					- rehypo manager redeem udl credit token for udl credit balance via `swapForExchangeBalance`
					- rehypo manager transfers exchanage balance collateral to hedging manager

		TODO: if stable lending (lev long), can only hedge against exchange balance (collateral == udl credit, asset == exchange balance)
			- when repaying 
				- swap udl credit borrowed for exchange balance at oracle rate interally with agaisnt rehypo manager
					- hedging manager sends udl credit borrowed to rehypo manager
					- repay loan with exchange balance recieved
						- free udl credit collateral
						
					- swap udl credit interally in to exchange balance
					- rehypo manager redeem udl credit token for udl credit balance via `swapForExchangeBalance`
					- rehypo manager transfers exchanage balance collateral to hedging manager
	*/
	
	function lend(address asset, address collateral, uint assetAmount, uint collateralAmount, address udlFeed) override external {

		require(
            settings.isAllowedHedgingManager(msg.sender) == true, 
            "not allowed hedging manager"
        );

		//https://docs.teller.org/teller-v2-protocol/l96ARgEDQcTgx4muwINt/personas/lenders/create-commitment

		require(lenderCommitmentIdMap[msg.sender][asset][collateral] == 0, "already lending");
		uint notional;

		if (collateral == address(exchange)) {
			//non stable lending (lev short), can only hedge against udl credit (collateral == exchange balance, asset == udl credit)
			require(
        		UnderlyingFeed(udlFeed).getUnderlyingAddr() == IUnderlyingCreditToken(asset).getUdlAsset(),
        		"bad udlFeed"
        	);
			uint256 udlAssetBal = IUnderlyingCreditProvider(asset).balanceOf(address(this));

			(,int udlPrice) = UnderlyingFeed(udlFeed).getLatestPrice();
			uint256 udlNotionalAmount = assetAmount.mul(1e18).div(uint256(udlPrice));

			//assetAmount / price = collateralAmount * leverage

			//before loan request
			if (udlAssetBal >= udlNotionalAmount){
				IUnderlyingCreditProvider(asset).swapBalanceForCreditTokens(address(this), udlNotionalAmount);
			} else {
				if (udlAssetBal > 0) {
					IUnderlyingCreditProvider(asset).swapBalanceForCreditTokens(address(this), udlAssetBal);
				}	
				IUnderlyingCreditProvider(asset).issueCredit(address(this), udlNotionalAmount.sub(udlAssetBal));

			}

			notional = udlNotionalAmount;
		} else {
			//stable lending (lev long), can only hedge against exchange balance (collateral == udl credit, asset == exchange balance) 
			
			uint256 assetBal = IERC20_2(asset).balanceOf(address(this));
			//before loan request
			if (assetBal < assetAmount){
				creditProvider.issueCredit(address(this), assetAmount.sub(assetBal));
				creditToken.swapForExchangeBalance(assetAmount.sub(assetBal));
			}

			notional = assetAmount;
		}

		//handle approval for commitment
		IERC20_2 tk = IERC20_2(asset);
        if (tk.allowance(address(this), tellerInterfaceAddr) > 0) {
            tk.safeApprove(tellerInterfaceAddr, 0);
        }
        tk.safeApprove(tellerInterfaceAddr, notional);
		
		/**
		* @notice Creates a loan commitment from a lender for a market.
		* @param _commitment The new commitment data expressed as a struct
		* @param _borrowerAddressList The array of borrowers that are allowed to accept loans using this commitment
		* @return commitmentId_ returns the commitmentId for the created commitment
		*/

		ITellerInterface.Commitment memory _commitment;
		
        _commitment.maxPrincipal = assetAmount;//uint256 maxPrincipal;
        _commitment.expiration;//uint32 expiration;TODO
        _commitment.maxDuration;//uint32 maxDuration;TODO
        _commitment.minInterestRate = 0;//uint16 minInterestRate;
        _commitment.collateralTokenAddress = collateral;//address collateralTokenAddress;
        _commitment.collateralTokenId = 0;//uint256 collateralTokenId;
        _commitment.maxPrincipalPerCollateralAmount = assetAmount.div(collateralAmount);//uint256 maxPrincipalPerCollateralAmount;
        _commitment.collateralTokenType = ITellerInterface.CommitmentCollateralType.ERC20;//CommitmentCollateralType collateralTokenType;
        _commitment.lender = address(this);//address lender;
        _commitment.marketId;//uint256 marketId;TODO
        _commitment.principalTokenAddress = asset;//address principalTokenAddress;

		address[] memory _borrowerAddressList = new address[](2);
		_borrowerAddressList[0] = address(this);
		_borrowerAddressList[1] = msg.sender;
		
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

    function borrow(address asset, address collateral, uint assetAmount, uint collateralAmount, address udlFeed) override external {
    	require(
            settings.isAllowedHedgingManager(msg.sender) == true, 
            "not allowed hedging manager"
        );

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

		require(
    		UnderlyingFeed(udlFeed).getUnderlyingAddr() == IUnderlyingCreditToken(asset).getUdlAsset(),
    		"bad udlFeed"
    	);

    	(,int udlPrice) = UnderlyingFeed(udlFeed).getLatestPrice();

        if (collateral == address(exchange)) {
			//(collateral == exchange balance, asset == udl credit)
			IERC20_2(collateral).safeTransferFrom(
	            msg.sender,
	            address(this), 
	            collateralAmount
	        );
		} else { 
			//(collateral == udl credit, asset == exchange balance)
			uint256 collateralAmountInAsset = collateralAmount.mul(uint256(udlPrice)).div(1e18);
			//assetAmount / leverage = collateralAmount * price

			IERC20_2(asset).safeTransferFrom(
	            msg.sender,
	            address(this), 
	            collateralAmountInAsset
	        );
			uint256 udlAssetBal = IUnderlyingCreditProvider(collateral).balanceOf(address(this));
	        //before borrow request, mint or credit the difference differing in collateral to rehypo manager
			if (udlAssetBal >= collateralAmount){
				IUnderlyingCreditProvider(asset).swapBalanceForCreditTokens(address(this), collateralAmount);
			} else {
				if (udlAssetBal > 0) {
					IUnderlyingCreditProvider(asset).swapBalanceForCreditTokens(address(this), udlAssetBal);
				}	
				IUnderlyingCreditProvider(asset).issueCredit(address(this), collateralAmount.sub(udlAssetBal));
			}
		}

	    uint256 _collateralTokenId = 0;//0 for erc20's
	    uint32 _loanDuration;//TODO

		uint256 _bidId = ITellerInterface(tellerInterfaceAddr).acceptCommitment(
		    lenderCommitmentIdMap[msg.sender][asset][collateral],
		    assetAmount,
		    collateralAmount,
		    _collateralTokenId,//0 for erc20's
		    collateral,
		    0, 
		    _loanDuration
		);

		if (collateral == address(exchange)) {
			//(collateral == exchange balance, asset == udl credit)
	        /*

	        - after borrow request
				- swap udl credit borrowed for exchange balance at orace rate interally with agaisnt rehypo manager
					- mint exchange balance to rehypo manager -> transfer to pool hedging manager
					- rehypo manage keeps udl credit token

			*/
			uint256 collateralBal = IERC20_2(collateral).balanceOf(address(this));
			uint256 assetAmountInCollateral = assetAmount.mul(uint256(udlPrice)).div(1e18);
			if (collateralBal < assetAmountInCollateral){
				creditProvider.issueCredit(address(this), assetAmountInCollateral.sub(collateralBal));
				creditToken.swapForExchangeBalance(assetAmountInCollateral.sub(collateralBal));
			}

			IERC20_2(collateral).safeTransfer(msg.sender, assetAmountInCollateral);
		} else {
			//(collateral == udl credit, asset == exchange balance)
			/*
			- after borrow request
				- swap exchange balance borrowed for udl credit at orace rate interally with agaisnt rehypo manager
					- withdraw (or mint the amount short) udl credit to rehypo manager -> transfer to pool hedging manager
					- rehypo manage keeps exchange balance
			*/

			uint256 udlAssetBal = IERC20_2(collateral).balanceOf(address(this));
			uint256 collateralAmountInAsset = assetAmount.mul(1e18).div(uint256(udlPrice));
			if (udlAssetBal >= collateralAmountInAsset){
				IUnderlyingCreditProvider(asset).swapBalanceForCreditTokens(address(this), collateralAmountInAsset);
			} else {
				if (udlAssetBal > 0) {
					IUnderlyingCreditProvider(collateral).swapBalanceForCreditTokens(address(this), udlAssetBal);
				}	
				IUnderlyingCreditProvider(collateral).issueCredit(address(this), collateralAmountInAsset.sub(udlAssetBal));
			}

			IERC20_2(collateral).safeTransfer(msg.sender, collateralAmountInAsset);
		}

		

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
    
    function transferTokensToCreditProvider(address tokenAddr) override external {}

    function transferTokensToVault(address tokenAddr) override external {}
}