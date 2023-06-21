pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "truffle/Assert.sol";
import "../../../contracts/finance/OptionToken.sol";
import "../../../contracts/utils/MoreMath.sol";
import "./Base.t.sol";

contract TestCoveredLiquidation is Base {
    
    function testLiquidationBeforeAllowed() public {
        
        underlying.reset(address(this));
        underlying.issue(address(this), 3 * underlyingBase);

        address _tk = writeCovered(3, ethInitialPrice, 10 days);

        OptionToken tk = OptionToken(_tk);

        tk.transfer(address(alice), 2 * volumeBase);

        Assert.equal(1 * volumeBase, tk.balanceOf(address(this)), "writer tk balance");
        Assert.equal(2 * volumeBase, tk.balanceOf(address(alice)), "alice tk balance");
            
        (bool success,) = address(alice).call(
            abi.encodePacked(
                alice.liquidateOptions.selector,
                abi.encode(_tk, address(alice))
            )
        );
        
        Assert.isFalse(success, "liquidate should fail");
    }

    function testLiquidationAtMaturityOTM() public {
        
        underlying.reset(address(this));
        underlying.issue(address(this), 2 * underlyingBase);
        
        int step = 40e18;

        address _tk = writeCovered(2, ethInitialPrice, 10 days);

        OptionToken tk = OptionToken(_tk);
        
        tk.transfer(address(alice), 2 * volumeBase);

        feed.setPrice(ethInitialPrice - step);
        time.setTimeOffset(10 days);

        uint b0 = underlying.balanceOf(address(this));
        Assert.equal(b0, 0, "underlying before liquidation");

        collateralManager.liquidateOptions(_tk, address(this));

        uint b1 = underlying.balanceOf(address(this));
        Assert.equal(b1, 2 * underlyingBase, "underlying after liquidation");

        Assert.equal(exchange.calcCollateral(address(this), true), 0, "writer final collateral");
        Assert.equal(alice.calcCollateral(), 0, "alice final collateral");

        Assert.equal(exchange.calcSurplus(address(this)), 0, "writer final surplus");
        Assert.equal(alice.calcSurplus(), 0, "alice final surplus");
    }

    function testLiquidateMultipleITM() public {
        
        underlying.reset(address(this));
        underlying.issue(address(this), 4 * underlyingBase);

        settings.setSwapRouterInfo(router, address(erc20));
        settings.setSwapRouterTolerance(105e4, 1e6);
        
        int step = 40e18;

        address _tk100 = writeCovered(2, ethInitialPrice, 100 days);
        address _tk200 = writeCovered(2, ethInitialPrice, 200 days);

        OptionToken tk100 = OptionToken(_tk100);
        OptionToken tk200 = OptionToken(_tk200);
        
        tk100.transfer(address(alice), 2 * volumeBase);
        tk200.transfer(address(alice), 2 * volumeBase);

        feed.setPrice(ethInitialPrice + step);

        time.setTimeOffset(100 days);
        collateralManager.liquidateOptions(_tk100, address(this));
        
        time.setTimeOffset(200 days);
        collateralManager.liquidateOptions(_tk200, address(this));
    }

    function writeCovered(
        uint volume,
        int strike, 
        uint timeToMaturity
    )
        public
        returns (address _tk)
    {
        IERC20(
            UnderlyingFeed(feed).getUnderlyingAddr()
        ).approve(address(exchange), volume * volumeBase);

        _tk = exchange.createSymbol(
            address(feed),
            IOptionsExchange.OptionType.CALL,
            uint(strike), 
            time.getNow() + timeToMaturity
        );

        IOptionsExchange.OpenExposureInputs memory oEi;

        oEi.symbols = new string[](1);
        oEi.volume = new uint[](1);
        oEi.isShort = new bool[](1);
        oEi.isCovered = new bool[](1);
        oEi.poolAddrs = new address[](1);
        oEi.paymentTokens = new address[](1);


        oEi.symbols[0] = IOptionToken(_tk).symbol();
        oEi.volume[0] = volume * volumeBase;
        oEi.isShort[0] = true;
        oEi.poolAddrs[0] = address(this);//poolAddr;
        oEi.isCovered[0] = true;
        //oEi.paymentTokens[0] = address(0); //exploiting default to save gas


        exchange.openExposure(
            oEi,
            address(this)
        );
    }
}