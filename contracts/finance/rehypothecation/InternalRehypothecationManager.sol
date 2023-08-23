pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseRehypothecationManager.sol";
import "../../interfaces/UnderlyingFeed.sol";
import "../../interfaces/IUnderlyingCreditToken.sol";
import "../../interfaces/IBaseHedgingManager.sol";
import "../../interfaces/IUnderlyingCreditProvider.sol";

contract InternalRehypothecationManager is BaseRehypothecationManager {
	uint constant _volumeBase = 1e18;

	mapping(address => mapping(address => mapping(address => uint256))) lenderCommitmentIdMap;
	mapping(address => mapping(address => mapping(address => uint256))) borrowerBidIdMap;
	mapping(address => mapping(address => mapping(address => uint256))) notionalExposureMap;
	mapping(address => mapping(address => mapping(address => uint256))) notionalExposureInExchangeBalMap;
	mapping(address => mapping(address => mapping(address => uint256))) collateralAmountMap;

	function notionalExposure(address account, address asset, address collateral) override external view returns (uint256) {
		return notionalExposureInExchangeBalMap[account][asset][collateral];
	}

	function borrowExposure(address account, address asset, address collateral) override external view returns (uint256) {
		return notionalExposureMap[account][asset][collateral];
	}

	function lend(address asset, address collateral, uint assetAmount, uint collateralAmount, address udlFeed) override external {

		require(
            settings.isAllowedHedgingManager(msg.sender) == true, 
            "not allowed hedging manager"
        );


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
			uint256 udlNotionalAmount = assetAmount.mul(_volumeBase).div(uint256(udlPrice));

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
		
		lenderCommitmentIdMap[msg.sender][asset][collateral]++;
		collateralAmountMap[msg.sender][asset][collateral] = collateralAmount;
	}

    function withdraw(address asset, address collateral, uint amount) override external {}

    function borrow(address asset, address collateral, uint assetAmount, uint collateralAmount, address udlFeed) override external {
    	require(
            settings.isAllowedHedgingManager(msg.sender) == true, 
            "not allowed hedging manager"
        );

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
			uint256 collateralAmountInAsset = collateralAmount.mul(uint256(udlPrice)).div(_volumeBase);
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

		if (collateral == address(exchange)) {
			//(collateral == exchange balance, asset == udl credit)
	        /*

	        - after borrow request
				- swap udl credit borrowed for exchange balance at orace rate interally with agaisnt rehypo manager
					- mint exchange balance to rehypo manager -> transfer to pool hedging manager
					- rehypo manage keeps udl credit token

			*/
			uint256 collateralBal = IERC20_2(collateral).balanceOf(address(this));
			uint256 assetAmountInCollateral = assetAmount.mul(uint256(udlPrice)).div(_volumeBase);
			if (collateralBal < assetAmountInCollateral){
				creditProvider.issueCredit(address(this), assetAmountInCollateral.sub(collateralBal));
				creditToken.swapForExchangeBalance(assetAmountInCollateral.sub(collateralBal));
			}

			IERC20_2(collateral).safeTransfer(msg.sender, assetAmountInCollateral);
			notionalExposureInExchangeBalMap[msg.sender][asset][collateral] = assetAmountInCollateral;
		} else {
			//(collateral == udl credit, asset == exchange balance)
			/*
			- after borrow request
				- swap exchange balance borrowed for udl credit at orace rate interally with agaisnt rehypo manager
					- withdraw (or mint the amount short) udl credit to rehypo manager -> transfer to pool hedging manager
					- rehypo manage keeps exchange balance
			*/

			uint256 udlAssetBal = IERC20_2(collateral).balanceOf(address(this));
			uint256 collateralAmountInAsset = assetAmount.mul(_volumeBase).div(uint256(udlPrice));
			if (udlAssetBal >= collateralAmountInAsset){
				IUnderlyingCreditProvider(asset).swapBalanceForCreditTokens(address(this), collateralAmountInAsset);
			} else {
				if (udlAssetBal > 0) {
					IUnderlyingCreditProvider(collateral).swapBalanceForCreditTokens(address(this), udlAssetBal);
				}	
				IUnderlyingCreditProvider(collateral).issueCredit(address(this), collateralAmountInAsset.sub(udlAssetBal));
			}

			IERC20_2(collateral).safeTransfer(msg.sender, collateralAmountInAsset);
			notionalExposureInExchangeBalMap[msg.sender][asset][collateral] = assetAmount;
		}

		

		borrowerBidIdMap[msg.sender][asset][collateral] = 1;
		notionalExposureMap[msg.sender][asset][collateral] = assetAmount;
    }
    
    function repay(address asset, address collateral, address udlFeed)  override external {

		require(lenderCommitmentIdMap[msg.sender][asset][collateral] > 0, "no outstanding loan");
		require(borrowerBidIdMap[msg.sender][asset][collateral] > 0, "no outstanding borrow");

		(,int udlPrice) = UnderlyingFeed(udlFeed).getLatestPrice();

		/*

		uint256 _collateralTokenId = 0;//0 for erc20's
	    uint32 _loanDuration = 7 days;//

		uint256 _bidId = ITellerInterface(tellerInterfaceAddr).acceptCommitment(
		    lenderCommitmentIdMap[msg.sender][asset][collateral],
		    assetAmount,
		    collateralAmount,
		    _collateralTokenId,//0 for erc20's
		    collateral,
		    0, 
		    _loanDuration
		);

		*/

		if (collateral == address(exchange)) {
			//(collateral == exchange balance, asset == udl credit)
			uint256 transferAmountInCollateral = notionalExposureMap[msg.sender][asset][collateral].mul(uint(udlPrice)).div(_volumeBase);
			IERC20_2(collateral).safeTransferFrom(
	            msg.sender,
	            address(this), 
	            transferAmountInCollateral
	        );
		} else { 
			//(collateral == udl credit, asset == exchange balance)

			uint256 transferAmountInAsset = notionalExposureMap[msg.sender][asset][collateral].mul(uint(udlPrice)).div(_volumeBase);
			uint256 udlCreditBal = IERC20_2(collateral).balanceOf(msg.sender);
			uint256 udlCreditBalInAsset = udlCreditBal.mul(uint(udlPrice)).div(_volumeBase);
			uint256 assetBal = IERC20_2(asset).balanceOf(msg.sender);
			IERC20_2(collateral).safeTransferFrom(
	            msg.sender,
	            address(this), 
	            udlCreditBal
	        );

	    	uint256 diffAmountInExchangeBalance;

			if (udlCreditBalInAsset >= transferAmountInAsset) {
				//transfer all udl credit bal, swap surplus into exchange bal, credit hedging manager for exchange bal diff
				diffAmountInExchangeBalance = udlCreditBalInAsset.sub(transferAmountInAsset);
				if (assetBal < diffAmountInExchangeBalance){
					creditProvider.issueCredit(address(this), diffAmountInExchangeBalance.sub(assetBal));
					creditToken.swapForExchangeBalance(diffAmountInExchangeBalance.sub(assetBal));
				}
				IERC20_2(asset).safeTransfer(msg.sender, diffAmountInExchangeBalance);
			} else {
				//transfer all, compute shortage amount, debit pool owner for exchange bal diff (protocol fees are charged for shortages)
				diffAmountInExchangeBalance = transferAmountInAsset.sub(udlCreditBalInAsset);
				creditProvider.processPayment(IBaseHedgingManager(msg.sender).pool(), address(this), diffAmountInExchangeBalance);
			}
		}

		if (collateral == address(exchange)) {
			//(collateral == exchange balance, asset == udl credit)
			//burn udl credit value
			IUnderlyingCreditToken(asset).burnBalance(notionalExposureMap[msg.sender][asset][collateral]);
			//rehypo manager transfers exchanage balance collateral to hedging manager
			IERC20_2(collateral).safeTransfer(msg.sender, collateralAmountMap[msg.sender][asset][collateral]);
		} else { 
			//(collateral == udl credit, asset == exchange balance)
			//burn exchange balance in excess of collateral value
			creditToken.burnBalance(notionalExposureMap[msg.sender][asset][collateral]);
			//burn udl credit of collateral value
			IUnderlyingCreditToken(collateral).burnBalance(collateralAmountMap[msg.sender][asset][collateral]);
			//transfers exchanage balance collateral to hedging manager
			IERC20_2(asset).safeTransfer(
				msg.sender,
				collateralAmountMap[msg.sender][asset][collateral].mul(uint(udlPrice)).div(_volumeBase)
			);
		}

		borrowerBidIdMap[msg.sender][asset][collateral] = 0;
		lenderCommitmentIdMap[msg.sender][asset][collateral] = 0;
		notionalExposureMap[msg.sender][asset][collateral] = 0;
		collateralAmountMap[msg.sender][asset][collateral] = 0;
    }
    
    function transferTokensToCreditProvider(address tokenAddr) override external {}

    function transferTokensToVault(address tokenAddr) override external {}
}