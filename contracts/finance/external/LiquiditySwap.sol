pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../interfaces/IERC20.sol";
import "../../interfaces/ICreditToken.sol";
import "../../interfaces/ICreditProvider.sol";
import "../../interfaces/external/ISwap.sol";


//https://raw.githubusercontent.com/nerve-finance/contracts/main/SwapUtils.sol

/*
	- owner of SwapFlashLoan contracts need to
		- upgrade Swap.sol 
		- mint enough lp tokens to cover enough requested stables
			- redeem lp tokens for stables
		- call swapTokenForCredit function on desired credit provider
			- hold as long as desired, redeem debt for stables at interest
			- deposit stables back to desired lp pool

		- call swapForExchangeBalance(uint value) if desire for exchange balance for using options

		- when redeeming (requestWithdraw) need to factor in lp:axial holder profit spit in contract
			-25% sent to axial holders
				- seperate contract that holds the funds before its sent back to sAxial holders?
					- claiamable contract that will allow saxial stakers to claim their share relative to their sAxial ownership
			-75% deposited back into liquidity pool

		- assumptions
			- apy on liquidity swap > base line aby on pool with no liquidity swap
		
		- pros:
			- more swap volume
			- more revenue
			- stakeholder in governance tokens for axial?
			- can burn credit for exchange balance and use it to pursue options strategies
		- cons:
			- non zero increase in credit risk reliant upon demand for option buyers and traders using DOD
*/

contract LiquiditySwap is Ownable {
	address creditProvider;
	address creditToken;
	address tokenPool;

	constructor(address _creditProvider, address _creditToken, address _tokenPool, address owner) {
		address creditProvider = _creditProvider;
		address creditToken = _creditToken;
		address tokenPool = _tokenPool;
		transferOwnerShip(owner);
	}

	function executeLiquiditySwap(uint256 amountUnderlying) ownlyGovernance external {
		ISwap(tokenPool).mintForLiquidtySwap(amountUnderlying);
		address[] memory pooledTokens = ISwap(tokenPool).getPooledTokens();
		address lpToken = ISwap(tokenPool).getLpToken();

		uint256[] memory minAmounts = new uint256[](pooledTokens.length);
		for (uint i=0; i<pooledTokens.length;i++) {
			minAmounts[i] = 0;
		}
		ISwap(tokenPool).removeLiquidity(
			IERC20(lpToken).balanceOf(address(this)),
			minAmounts,
			0
		);

		for (uint i=0; i<pooledTokens.length;i++) {
			ICreditProvider(creditProvider).swapTokenForCredit(
				address(this),
				pooledTokens[i],
				IERC20(pooledTokens[i]).balanceOf(address(this))
			)
		}
	}

	function executeCreditSwap(uint256 value) ownlyGovernance external{
		//burning credit for exchange balance + interest, NOTE: INTEREST PAYOUT PERIOD WILL RESET WHEN CALLED
		ICreditToken(creditToken).swapForExchangeBalance(value);
	}

	function executeRequestWithdraw() ownlyGovernance external {
		//burning credit for underlying tokens + interest, NOTE: INTEREST PAYOUT PERIOD WILL RESET WHEN CALLED
		ICreditToken(creditToken).requestWithdraw();
	}

	function executeTransfer(address token, address to, uint256 amount) ownlyOwner external {
		if (amount > 0) {
            IERC20(token).safeTransfer(to, amount);
        }
	}
}