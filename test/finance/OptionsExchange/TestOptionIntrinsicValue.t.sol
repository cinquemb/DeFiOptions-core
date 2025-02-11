pragma solidity >=0.6.0;

import "truffle/Assert.sol";
import "../../../contracts/utils/MoreMath.sol";
import "../../common/utils/MoreAssert.t.sol";
import "./Base.t.sol";

contract TestOptionIntrinsicValue is Base {

    function testCallIntrinsictValue() public {

        int step = 30e18;
        depositTokens(address(bob), upperVol);


        exchange.createSymbol(address(feed), CALL, uint(ethInitialPrice), time.getNow() + 5 days);
        addSymbol(uint(ethInitialPrice), time.getNow() + 5 days);
        (bool success1,) = address(bob).call(
            abi.encodePacked(
                bob.writeOption.selector,
                abi.encode(CALL, ethInitialPrice, 5 days, pool)
            )
        );


        feed.setPrice(ethInitialPrice - step);
        Assert.equal(int(exchange.calcIntrinsicValue(address(feed), CALL, uint(ethInitialPrice), time.getNow() + 5 days)), 0, "quote below strike");

        feed.setPrice(ethInitialPrice);
        Assert.equal(int(exchange.calcIntrinsicValue(address(feed), CALL, uint(ethInitialPrice), time.getNow() + 5 days)), 0, "quote at strike");
        
        feed.setPrice(ethInitialPrice + step);
        Assert.equal(int(exchange.calcIntrinsicValue(address(feed), CALL, uint(ethInitialPrice), time.getNow() + 5 days)), step, "quote above strike");
        
        Assert.equal(bob.calcCollateral(), upperVol + uint(step), "call collateral");
    }

    function testPutIntrinsictValue() public {

        int step = 40e18;
        depositTokens(address(bob), upperVol);
        address _tk = bob.writeOption(PUT, ethInitialPrice, 1 days, pool);
        bob.transferOptions(address(alice), _tk, 1);

        feed.setPrice(ethInitialPrice - step);
        Assert.equal(int(exchange.calcIntrinsicValue(_tk)), step, "quote below strike");

        feed.setPrice(ethInitialPrice);
        Assert.equal(int(exchange.calcIntrinsicValue(_tk)), 0, "quote at strike");
        
        feed.setPrice(ethInitialPrice + step);
        Assert.equal(int(exchange.calcIntrinsicValue(_tk)), 0, "quote above strike");
                
        Assert.equal(bob.calcCollateral(), upperVol, "put collateral");
    }

    function testCollateralAtDifferentMaturities() public {

        uint ct1 = MoreMath.sqrtAndMultiply(30, upperVol);
        depositTokens(address(bob), ct1);

        exchange.createSymbol(address(feed), CALL, uint(ethInitialPrice), time.getNow() + 30 days);
        addSymbol(uint(ethInitialPrice), time.getNow() + 30 days);
        (bool success1,) = address(bob).call(
            abi.encodePacked(
                bob.writeOption.selector,
                abi.encode(CALL, ethInitialPrice, 30 days, pool)
            )
        );


        MoreAssert.equal((success1 == true )? 1 : 0, 1, cBase, "wrote");


        MoreAssert.equal(time.getNow() + 30 days, settings.exchangeTime() + 30 days, cBase, "exchange time");
        MoreAssert.equal(bob.calcCollateral(), ct1, cBase, "collateral at 30d");

        uint ct2 = MoreMath.sqrtAndMultiply(10, upperVol);
        time.setTimeOffset(20 days);
        MoreAssert.equal(bob.calcCollateral(), ct2, cBase, "collateral at 10d");

        uint ct3 = MoreMath.sqrtAndMultiply(5, upperVol);
        time.setTimeOffset(25 days);
        MoreAssert.equal(bob.calcCollateral(), ct3, cBase, "collateral at 5d");

        uint ct4 = MoreMath.sqrtAndMultiply(1, upperVol);
        time.setTimeOffset(29 days);
        MoreAssert.equal(bob.calcCollateral(), ct4, cBase, "collateral at 1d");
    }

    function testCollateralForDifferentStrikePrices() public {
        
        int step = 40e18;
        uint vBase = 1e24;

        depositTokens(address(bob), 1500 * vBase);

        exchange.createSymbol(address(feed), CALL, uint(ethInitialPrice-step), time.getNow() + 10 days);
        addSymbol(uint(ethInitialPrice-step), time.getNow() + 10 days);
        (bool success1,) = address(bob).call(
            abi.encodePacked(
                bob.writeOption.selector,
                abi.encode(CALL, ethInitialPrice-step, 10 days, pool)
            )
        );

        uint ct1 = MoreMath.sqrtAndMultiply(10, upperVol) + uint(step);
        MoreAssert.equal(bob.calcCollateral(), ct1, cBase, "collateral ITM");

        exchange.createSymbol(address(feed), CALL, uint(ethInitialPrice+step), time.getNow() + 10 days);
        addSymbol(uint(ethInitialPrice+step), time.getNow() + 10 days);
        (bool success2,) = address(bob).call(
            abi.encodePacked(
                bob.writeOption.selector,
                abi.encode(CALL, ethInitialPrice+step, 10 days, pool)
            )
        );

        uint ct2 = MoreMath.sqrtAndMultiply(10, upperVol);
        MoreAssert.equal(bob.calcCollateral(), ct1 + ct2, cBase, "collateral OTM");
    }
}