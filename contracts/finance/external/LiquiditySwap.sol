pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../interfaces/IERC20.sol";
import "../../interfaces/ICreditToken.sol";
import "../../interfaces/ICreditProvider.sol";
import "../../interfaces/external/ISwapFlashLoan.sol";
import "../../interfaces/external/ISwapUtils.sol";


//https://raw.githubusercontent.com/nerve-finance/contracts/main/SwapUtils.sol

/*
	- onwer of swapflashloan contracts need to
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
			- apy on liquidy swap > base line aby on pool with no liquidity swap
		- pros:
			- more swap volume
			- more revenue
			- stakeholder in governance tokens for axial?
			- can burn credit for exchange balance and use it to pursue options strategies
		- cons:
			- non zero increase in credit risk reliant upon demand for option buyers and traders using DOD
*/


contract SwapFlashLoan {
	...existing methods;
	
	address private liquiditySwapAddr;

	function setLiquiditySwapAddr(address addr) onlyOwner {
		liquiditySwapAddr = addr;
	}

	function _xp(
        uint256[] memory balances,
        uint256[] memory precisionMultipliers
    ) internal pure returns (uint256[] memory) {
        uint256 numTokens = balances.length;
        require(
            numTokens == precisionMultipliers.length,
            "Balances must match multipliers"
        );
        uint256[] memory xp = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; i++) {
            xp[i] = balances[i].mul(precisionMultipliers[i]);
        }
        return xp;
    }

	function mintForLiquidtySwap(uint256 underlyingDesiredTokenAmount) onlyLiquiditySwap {
		/*

			mintmount = totalLPTokenSupply * (underlyingDesiredTokenAmount / total amount underlying tokens);
		*/

        ISwapUtils.SwapUtils.Swap swapInfo = ISwapFlashLoan(tokenPool).swapStorage();
        uint256[] normedBalances = _xp(swapInfo.balances, swapInfo.tokenPrecisionMultipliers);

        uint256 normedBalanceSum = 0;
        for(uint i=0;i<normedBalances.length;i++){
        	normedBalanceSum += normedBalances[i];
        }

        require(underlyingDesiredTokenAmount < normedBalanceSum, "exceeds balances");
        uint256 toMint = self.lpToken.totalSupply().mul(underlyingDesiredTokenAmount).div(normedBalanceSum);
		self.lpToken.mint(msg.sender, toMint);
	}

	modifier onlyLiquiditySwap() {
		require(msg.sender == liquiditySwapAddr, "only liquidity swap");
		_;
	}
}


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
		ISwapFlashLoan(tokenPool).mintForLiquidtySwap(amountUnderlying);
		ISwapUtils.SwapUtils.Swap swapInfo = ISwapFlashLoan(tokenPool).swapStorage();

		ISwapFlashLoan(tokenPool).removeLiquidity(
			uint256 amount,
			uint256[] calldata minAmounts,
			uint256 deadline
		);

		for (uint i=0; i<swapInfo.pooledTokens.length;i++) {
			ICreditProvider(creditProvider).swapTokenForCredit(address(this), address(swapInfo.pooledTokens[i]), swapInfo.pooledTokens[i].balanceOf(address(this)))
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