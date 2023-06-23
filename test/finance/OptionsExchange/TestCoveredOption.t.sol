pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "truffle/Assert.sol";
import "../../../contracts/finance/OptionToken.sol";
import "../../../contracts/utils/MoreMath.sol";
import "./Base.t.sol";

contract TestCoveredOption is Base {
    
    function testWriteCoveredCall() public {

        underlying.reset(address(this));
        underlying.issue(address(this), underlyingBase);

        address _tk = writeCovered(1, ethInitialPrice, 10 days);

        OptionToken tk = OptionToken(_tk);
        
        Assert.equal(volumeBase, tk.balanceOf(address(this)), "tk balance");
        Assert.equal(volumeBase, tk.writtenVolume(address(this)), "tk writtenVolume");
        Assert.equal(0, tk.uncoveredVolume(address(this)), "tk uncoveredVolume");
        Assert.equal(0, exchange.calcCollateral(address(this), true), "exchange collateral");
    }
    
    function testBurnCoveredCall() public {

        underlying.reset(address(this));
        underlying.issue(address(this), 2 * underlyingBase);

        address _tk = writeCovered(2, ethInitialPrice, 10 days);

        OptionToken tk = OptionToken(_tk);
        tk.burn(volumeBase);
        
        Assert.equal(volumeBase, tk.balanceOf(address(this)), "tk balance t0");
        Assert.equal(volumeBase, tk.writtenVolume(address(this)), "tk writtenVolume t0");
        Assert.equal(underlyingBase, underlying.balanceOf(address(this)), "underlying balance t0");
        Assert.equal(0, tk.uncoveredVolume(address(this)), "tk uncoveredVolume t0");
        Assert.equal(0, exchange.calcCollateral(address(this), true), "exchange collateral t0");

        tk.burn(volumeBase);
        
        Assert.equal(0, tk.balanceOf(address(this)), "tk balance t1");
        Assert.equal(0, tk.writtenVolume(address(this)), "tk writtenVolume t1");
        Assert.equal(2 * underlyingBase, underlying.balanceOf(address(this)), "underlying balance t1");
        Assert.equal(0, tk.uncoveredVolume(address(this)), "tk uncoveredVolume t1");
        Assert.equal(0, exchange.calcCollateral(address(this), true), "exchange collateral t1");
    }

    function testBurnCollateral() public {
        
        erc20.reset(address(this));

        uint ct20 = MoreMath.sqrtAndMultiply(20, upperVol);
        
        depositTokens(address(this), ct20);

        address _tk1 = exchange.createSymbol(
            address(feed),
            PUT,
            uint(ethInitialPrice), 
            time.getNow() + 20 days
        );

        IOptionsExchange.OpenExposureInputs memory oEi;

        oEi.symbols = new string[](1);
        oEi.volume = new uint[](1);
        oEi.isShort = new bool[](1);
        oEi.isCovered = new bool[](1);
        oEi.poolAddrs = new address[](1);
        oEi.paymentTokens = new address[](1);


        oEi.symbols[0] = IOptionToken(_tk1).symbol();
        oEi.volume[0] = volumeBase;
        oEi.isShort[0] = true;
        oEi.poolAddrs[0] = address(this);//poolAddr;
        //oEi.isCovered[0] = false; //expoliting default to save gas
        //oEi.paymentTokens[0] = address(0); //exploiting default to save gas


        exchange.openExposure(
            oEi,
            address(this)
        );

        Assert.equal(exchange.calcCollateral(address(this), true), ct20, "writer collateral t0");

        underlying.reset(address(this));
        underlying.issue(address(this), 2 * underlyingBase);

        address _tk2 = writeCovered(2, ethInitialPrice, 10 days);

        Assert.equal(exchange.calcCollateral(address(this), true), ct20, "writer collateral t1");

        OptionToken(_tk1).burn(volumeBase / 2);

        Assert.equal(exchange.calcCollateral(address(this), true), ct20 / 2, "writer collateral t2");

        OptionToken(_tk2).burn(volumeBase);

        Assert.equal(OptionToken(_tk1).balanceOf(address(this)), volumeBase / 2, "balanceOf tk1");
        Assert.equal(OptionToken(_tk1).writtenVolume(address(this)), volumeBase / 2, "writtenVolume tk1");
        Assert.equal(OptionToken(_tk2).balanceOf(address(this)), volumeBase, "balanceOf tk2");
        Assert.equal(OptionToken(_tk2).writtenVolume(address(this)), volumeBase, "writtenVolume tk2");
    }

    function testMixedCollateral() public {
        
        erc20.reset(address(this));

        uint ct10 = MoreMath.sqrtAndMultiply(10, upperVol);
        uint ct20 = MoreMath.sqrtAndMultiply(20, upperVol);
        
        depositTokens(address(this), ct20);

        address _tk1 = exchange.createSymbol(
            address(feed),
            PUT,
            uint(ethInitialPrice), 
            time.getNow() + 20 days
        );

        IOptionsExchange.OpenExposureInputs memory oEi;

        oEi.symbols = new string[](1);
        oEi.volume = new uint[](1);
        oEi.isShort = new bool[](1);
        oEi.isCovered = new bool[](1);
        oEi.poolAddrs = new address[](1);
        oEi.paymentTokens = new address[](1);


        oEi.symbols[0] = IOptionToken(_tk1).symbol();
        oEi.volume[0] = volumeBase;
        oEi.isShort[0] = true;
        oEi.poolAddrs[0] = address(this);//poolAddr;
        //oEi.isCovered[0] = false; //expoliting default to save gas
        //oEi.paymentTokens[0] = address(0); //exploiting default to save gas


        exchange.openExposure(
            oEi,
            address(this)
        );

        Assert.equal(exchange.calcCollateral(address(this), true), ct20, "writer collateral t0");

        underlying.reset(address(this));
        underlying.issue(address(this), 2 * underlyingBase);

        settings.setSwapRouterInfo(router, address(erc20));
        settings.setSwapRouterTolerance(105e4, 1e6);
        
        int step = 40e18;

        address _tk2 = writeCovered(2, ethInitialPrice, 10 days);

        OptionToken tk = OptionToken(_tk2);
        
        tk.transfer(address(alice), 2 * volumeBase);

        feed.setPrice(ethInitialPrice + step);
        time.setTimeOffset(10 days);

        Assert.equal(exchange.calcCollateral(address(this), true), ct10, "writer collateral t1");

        collateralManager.liquidateOptions(_tk2, address(this));
        tk.redeem(address(alice));

        Assert.equal(exchange.calcCollateral(address(this), true), ct10, "writer collateral t2");

        time.setTimeOffset(20 days);

        collateralManager.liquidateOptions(_tk1, address(this));

        Assert.equal(exchange.calcCollateral(address(this), true), 0, "writer collateral t3");
        Assert.equal(exchange.calcSurplus(address(this)), ct20, "writer final surplus");
    }

    function writeCovered(
        uint volume,
        int strike, 
        uint timeToMaturity
    )
        public
        returns (address _tk)
    {
        ERC20Mock mock = ERC20Mock(UnderlyingFeed(feed).getUnderlyingAddr());

        uint f = volumeBase;
        uint d = mock.decimals();
        if (d < 18) {
            f = f / (10 ** (18 - d));
        }
        if (d > 18) {
            f = f * (10 ** (d - 18));
        }

        mock.approve(address(exchange), volume * f);

        _tk = exchange.createSymbol(
            address(feed),
            CALL,
            uint(strike), 
            time.getNow() + timeToMaturity
        );

        addSymbol(uint(strike), time.getNow() + timeToMaturity);

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
        oEi.poolAddrs[0] = pool;//poolAddr;
        oEi.isCovered[0] = true;
        //oEi.paymentTokens[0] = address(0); //exploiting default to save gas

        (bool success,) = address(this).call(
            abi.encodePacked(
                exchange.openExposure.selector,
                abi.encode(oEi, address(this))
            )
        );

        Assert.equal(success,true, "covered option written");
    }
}