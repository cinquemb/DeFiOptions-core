pragma solidity >=0.6.0;

import "truffle/Assert.sol";
import "./Base.t.sol";

contract TestMulticoinTrading is Base {

    event LogUint(string, uint);

    ERC20Mock stablecoinA;
    ERC20Mock stablecoinB;
    ERC20Mock stablecoinC;

    uint optionBuyPrice;
    uint optionSellPrice;

/* testBuyWithMultipleCoins

    Initialize the LiquidityPool
    Trader A deposits the amount of 20*P Stablecoins A in the LiquidityPool
    Trader B buys an option from the pool paying the amount of P with Stablecoin B
    Trader C buys an option from the pool paying the amount of P with Stablecoin C
    Verify that all options were issued correctly and that the liquidity pool balance is 22*P
*/
    function testBuyWithMultipleCoins() public {

        stablecoinA = erc20;
        stablecoinB = ERC20Mock(deployer.getContractAddress("StablecoinB"));
        stablecoinC = ERC20Mock(deployer.getContractAddress("StablecoinC"));

        addSymbol();

        (optionBuyPrice,) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);
        (optionSellPrice,) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);

        //emit LogUint("0.optionBuyPrice is", optionBuyPrice);
        //emit LogUint("0.optionSellPrice is", optionSellPrice);

        uint decimals_diff = 0;

        // Trader A deposits the amount of 10*P Stablecoins A in the LiquidityPool
        PoolTrader userA = createPoolTrader(address(stablecoinA));
        uint volumeA = 20; // this volume is base by Options, not decimals
        uint amount = volumeA * optionBuyPrice;

        stablecoinA.issue(address(this), amount);
        stablecoinA.approve(address(pool), amount);
        IGovernableLiquidityPool(pool).depositTokens(address(userA), address(stablecoinA), amount);

        Assert.equal(IERC20(pool).balanceOf(address(userA)), amount, "userA stablecoinA after deposit");
        emit LogUint("1.balanceOf(pool) userA deposit", exchange.balanceOf(address(pool)));
        uint volume = 1 * volumeBase;

        // Trader B buys an option from the pool paying the amount of P with Stablecoin B
        PoolTrader userB = createPoolTrader(address(stablecoinB));
        decimals_diff = 1e9;
        stablecoinB.issue(address(userB), volume * optionBuyPrice / decimals_diff);

        address(userB).call(
            abi.encodePacked(
                userB.buyFromPool.selector,
                abi.encode(symbol, optionBuyPrice, volume)
            )
        );
        
        OptionToken tk_B = OptionToken(symbolAddr);
        Assert.equal(tk_B.balanceOf(address(userB)), volume, "userB options");
        emit LogUint("1.balanceOf(pool) after userB buy", exchange.balanceOf(address(pool)));

        // Trader C buys an option from the pool paying the amount of P with Stablecoin C
        PoolTrader userC = createPoolTrader(address(stablecoinC));
        decimals_diff = 1e12;
        stablecoinC.issue(address(userC), volume * optionBuyPrice / decimals_diff);

        address(userC).call(
            abi.encodePacked(
                userC.buyFromPool.selector,
                abi.encode(symbol, optionBuyPrice, volume)
            )
        );
        OptionToken tk_C = OptionToken(symbolAddr);
        Assert.equal(tk_C.balanceOf(address(userC)), volume, "userC options");

        emit LogUint("1.balanceOf(pool) after userC buy",exchange.balanceOf(address(pool)));

        // Verify that all options were issued correctly and that the liquidity pool balance is 22*P
        Assert.equal(
            exchange.balanceOf(address(pool)),
            22 * optionBuyPrice,
            "get pool balance from exchange"
        );
    }

/* testBuyWithCombinationOfCoins

    Initialize the LiquidityPool
    Trader A deposits the amount of 20*P Stablecoins A in the LiquidityPool
    Trader B deposits the amount of P/2 Stablecoins B in the OptionsExchange
    Trader B deposits the amount of P/2 Stablecoins C in the OptionsExchange
    Trader B buys an option from the pool paying with his exchange balance
    Verify that the option was issued correctly and that the liquidity pool balance is 21*P
*/
    function testBuyWithCombinationOfCoins() public {

        stablecoinA = erc20;
        stablecoinB = ERC20Mock(deployer.getContractAddress("StablecoinB"));
        stablecoinC = ERC20Mock(deployer.getContractAddress("StablecoinC"));

        addSymbol();

        (optionBuyPrice,) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);
        (optionSellPrice,) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);

        emit LogUint("0.optionBuyPrice is", optionBuyPrice);
        emit LogUint("0.optionSellPrice is", optionSellPrice);

        uint decimals_diff = 0;
        uint amount = 0;
        uint totalBalance_userB = 0;

        // Trader A deposits the amount of 20*P Stablecoins A in the LiquidityPool
        PoolTrader userA = createPoolTrader(address(stablecoinA));
        uint volumeA = 20; // this volume is base by Options, not decimals
        amount = volumeA*optionBuyPrice;

        stablecoinA.issue(address(this), amount);
        stablecoinA.approve(address(pool), amount);
        IGovernableLiquidityPool(pool).depositTokens(address(userA), address(stablecoinA), amount);

        Assert.equal(IERC20(pool).balanceOf(address(userA)), amount, "userA stablecoinA after deposit");
        emit LogUint("2.balanceOf(pool) userA deposit", exchange.balanceOf(address(pool)));
        
        // Trader B deposits the amount of P/2 Stablecoins B in the OptionsExchange
        PoolTrader userB = createPoolTrader(address(stablecoinB)); 
        decimals_diff = 1e9; // StablecoinB decimals is 9, diff=1e/(18-9)
        amount = optionBuyPrice / 2 / decimals_diff; // optionBuyPrice decimals is 18

        stablecoinB.issue(address(this), amount);
        emit LogUint("2.amount(stB) userB issue",amount);

        stablecoinB.approve(address(exchange), amount);
        exchange.depositTokens(address(userB), address(stablecoinB), amount);
        
        emit LogUint("2.balanceOf(ex) userB deposit", exchange.balanceOf(address(userB)));

        totalBalance_userB = amount * decimals_diff;        
        Assert.equal(exchange.balanceOf(address(userB)), totalBalance_userB, "userB stablecoinB after deposit");
        
        // Trader B deposits the amount of P/2 Stablecoins C in the OptionsExchange
        decimals_diff = 1e12; // StablecoinC decimals is 6,diff=1e/(18-6)
        amount = optionBuyPrice / 2 / decimals_diff; // optionBuyPrice decimals is 18

        stablecoinC.issue(address(this), amount);
        emit LogUint("2.amount(stC) userB issue", amount);

        stablecoinC.approve(address(exchange), amount);
        exchange.depositTokens(address(userB), address(stablecoinC), amount);
        
        emit LogUint("2.balanceOf(ex) userB deposit", exchange.balanceOf(address(userB)));
        totalBalance_userB = totalBalance_userB+amount*decimals_diff;
        Assert.equal(
            exchange.balanceOf(address(userB)),
            totalBalance_userB,
            "userB stablecoinC after deposit"
        );

        // Trader B buys an option from the pool paying with his exchange balance
        uint volume = 1 * volumeBase;
        decimals_diff = 1e9;
        stablecoinB.issue(address(userB), volume * optionBuyPrice / decimals_diff);

        address(userB).call(
            abi.encodePacked(
                userB.buyFromPool.selector,
                abi.encode(symbol, optionBuyPrice, volume)
            )
        );
        
        OptionToken tk = OptionToken(symbolAddr);
        Assert.equal(tk.balanceOf(address(userB)), volume, "userB options");
        emit LogUint("2.balanceOf(pool) after userB buy", exchange.balanceOf(address(pool)));
        
        // Verify that the option was issued correctly and that the liquidity pool balance is 21*P
        Assert.equal(
            exchange.balanceOf(address(pool)),
            21 * optionBuyPrice,
            "get pool balance from exchange"
        );
    }

/* testSellAndWithdrawCombinationOfCoins

    Initialize the LiquidityPool
    Trader A deposits the amount of 3*P/4 Stablecoins A in the LiquidityPool
    Trader A deposits the amount of 3*P/4 Stablecoins B in the LiquidityPool
    Trader B deposits the amount of 10*P Stablecoins C in the OptionsExchange
    Trader B writes an option in the OptionsExchange
    Trader B sells his option to the LiquidityPool
    The option expires OTM (out-of-the-money)
    Trader B withdraws all his exchange balance
    Verify that Trader B balances is a combination of Stablecoins “A”, “B” and “C” whose value add up to 11*P
*/
    function testSellAndWithdrawCombinationOfCoins() public {

        stablecoinA = erc20;
        stablecoinB = ERC20Mock(deployer.getContractAddress("StablecoinB"));
        stablecoinC = ERC20Mock(deployer.getContractAddress("StablecoinC"));

        addSymbol();

        (optionBuyPrice,) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);
        (optionSellPrice,) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);

        emit LogUint("0.optionBuyPrice is", optionBuyPrice);
        emit LogUint("0.optionSellPrice is", optionSellPrice);

        uint decimals_diff = 0;
        uint amount = 0;
        uint pool_total = 0;

        //Trader A deposits the amount of 3*P/4 Stablecoins A in the LiquidityPool
        PoolTrader userA = createPoolTrader(address(stablecoinA));  
        amount = 3 * optionSellPrice / 4;

        stablecoinA.issue(address(this), amount);
        stablecoinA.approve(address(pool), amount);
        IGovernableLiquidityPool(pool).depositTokens(address(userA), address(stablecoinA), amount);
        pool_total = amount;

        Assert.equal(IERC20(pool).balanceOf(address(userA)), pool_total, "userA stablecoinA after deposit");
        emit LogUint("3.balanceOf(pool) userA deposit", exchange.balanceOf(address(pool)));

        // Trader A deposits the amount of 3*P/4 Stablecoins B in the LiquidityPool
        decimals_diff = 1e9;
        amount = 3 * optionSellPrice / 4 / decimals_diff;

        stablecoinB.issue(address(this), amount);
        stablecoinB.approve(address(pool), amount);
        IGovernableLiquidityPool(pool).depositTokens(address(userA), address(stablecoinB), amount);
        pool_total = pool_total + amount * decimals_diff;

        Assert.equal(IERC20(pool).balanceOf(address(userA)), pool_total, "userA stablecoinB after deposit");
        emit LogUint("3.balanceOf(pool) userA deposit", exchange.balanceOf(address(pool)));

        // Trader B deposits the amount of 10*P Stablecoins C in the OptionsExchange
        PoolTrader userB = createPoolTrader(address(stablecoinA));  

        decimals_diff = 1e12;
        amount = 10 * optionSellPrice / decimals_diff;

        stablecoinC.issue(address(this), amount);
        stablecoinC.approve(address(exchange), amount);
        exchange.depositTokens(address(userB), address(stablecoinC), amount);
        
        emit LogUint("3.balanceOf(ex) userB deposit", exchange.balanceOf(address(userB)));
        Assert.equal(
            exchange.balanceOf(address(userB)),
            amount * decimals_diff,
            "userB stablecoinC after deposit"
        );

        // Trader B writes an option in the OptionsExchange
        uint test_strike = 550e18;
        emit LogUint("3.balanceOf(ex) userB write", exchange.balanceOf(address(userB)));

        // Trader B sells his option to the LiquidityPool
        uint volume = 1 * volumeBase;
        (uint sellPrice,) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);

        
        (bool success,) = address(userB).call(
            abi.encodePacked(
                userB.sellToPool.selector,
                abi.encode(symbol, sellPrice, volume)
            )
        );

        Assert.equal(success,true, "userB sold to pool");

        emit LogUint("3.balanceOf(ex) userB selltopool", exchange.balanceOf(address(userB)));
        emit LogUint("3.userB surplus before liquidate", exchange.calcSurplus(address(userB)));

        // The option expires OTM (out-of-the-money)
        uint step = 40e18;
        feed.setPrice(int(test_strike - step));
        time.setTimeOffset(30 days);
        
        (bool success1,) = address(userB).call(
            abi.encodePacked(
                collateralManager.liquidateOptions.selector,
                abi.encode(symbolAddr, address(userB))
            )
        );
        emit LogUint("3.userB surplus after liquidate", exchange.calcSurplus(address(userB)));

        // Trader B withdraws all his exchange balance
        emit LogUint("3.balanceOf(ex) userB after liquidate", exchange.balanceOf(address(userB)));
        userB.withdrawTokens(exchange.calcSurplus(address(userB)));
        Assert.equal(
            exchange.balanceOf(address(userB)),
            0,
            "userB exchange balance is zero after withdraw."
        );

        // Verify that Trader B balances is a combination of Stablecoins “A”, “B” and “C” whose value add up to 11*P
        Assert.notEqual(stablecoinA.balanceOf(address(userB)), 0, "stablecoinA balance not zero");
        Assert.notEqual(stablecoinB.balanceOf(address(userB)), 0, "stablecoinB balance not zero");
        Assert.notEqual(stablecoinC.balanceOf(address(userB)), 0, "stablecoinC balance not zero");
        uint totalValue =
            stablecoinA.balanceOf(address(userB)) +
            stablecoinB.balanceOf(address(userB)) * 1e9 +
            stablecoinC.balanceOf(address(userB)) * 1e12;

        emit LogUint("3.balanceOf(total) userB", totalValue);
        Assert.equal(optionSellPrice * 11, totalValue, "userB total value is 6*op");
    }
}
