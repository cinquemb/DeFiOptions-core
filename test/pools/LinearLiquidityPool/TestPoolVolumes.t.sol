pragma solidity >=0.6.0;

import "truffle/Assert.sol";
import "./Base.t.sol";

contract TestPoolVolumes is Base {

    function testPartialBuyingVolume() public {

        createTraders();

        addSymbol();

        uint cUnit = calcCollateralUnit();

        depositInPool(address(bob), 10 * cUnit);
        erc20.issue(address(alice), 5 * cUnit);

        (uint p1, uint v1) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);

        (bool success1,) = address(alice).call(
            abi.encodePacked(
                alice.buyFromPool.selector,
                abi.encode(symbol, p1, v1 / 2)
            )
        );

        (, uint v2) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);

        Assert.equal(v2, v1 / 2 + err, "volume after buying");
    }

    function testFullBuyingVolume() public {

        createTraders();

        addSymbol();

        uint cUnit = calcCollateralUnit();

        depositInPool(address(bob), 10 * cUnit);
        erc20.issue(address(alice), 5 * cUnit);

        (uint p1, uint v1) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);
        (bool success1,) = address(alice).call(
            abi.encodePacked(
                alice.buyFromPool.selector,
                abi.encode(symbol, p1, v1)
            )
        );
        (, uint v2) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);

        Assert.equal(v2, 0, "volume after buying");
    }

    function testPartialSellingVolume() public {

        createTraders();

        addSymbol();

        uint cUnit = calcCollateralUnit();

        depositInPool(address(bob), 1 * cUnit);
        erc20.issue(address(alice), 10 * cUnit);
        alice.depositInExchange(10 * cUnit);

        (uint p1, uint v1) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);        
        (bool success1,) = address(alice).call(
            abi.encodePacked(
                alice.sellToPool.selector,
                abi.encode(symbol, p1, v1 / 2)
            )
        );
        (, uint v2) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);

        Assert.equal(v2, v1 / 2 + err, "volume after selling");
    }

    function testFullSellingVolume() public {

        createTraders();

        addSymbol();

        uint cUnit = calcCollateralUnit();

        depositInPool(address(bob), 1 * cUnit);
        erc20.issue(address(alice), 10 * cUnit);
        alice.depositInExchange(10 * cUnit);

        (uint p1, uint v1) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);
        (bool success1,) = address(alice).call(
            abi.encodePacked(
                alice.sellToPool.selector,
                abi.encode(symbol, p1, v1)
            )
        );
        (, uint v2) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);

        Assert.equal(v2, 0, "volume after selling");
    }

    function testPartialBuyingThenFullSellingVolume() public {

        createTraders();

        addSymbol();

        uint cUnit = calcCollateralUnit();

        depositInPool(address(bob), 10 * cUnit);
        erc20.issue(address(alice), 5 * cUnit);

        (uint p1, uint v1) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);
        (bool success1,) = address(alice).call(
            abi.encodePacked(
                alice.buyFromPool.selector,
                abi.encode(symbol, p1, v1 / 2)
            )
        );
        (, uint v2) = IGovernableLiquidityPool(pool).queryBuy(symbol, true);

        Assert.equal(v2, v1 / 2 + err, "volume after buying");

        erc20.issue(address(bob), 100 * cUnit);
        bob.depositInExchange(100 * cUnit);

        (uint p3, uint v3) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);
        (bool success2,) = address(bob).call(
            abi.encodePacked(
                bob.sellToPool.selector,
                abi.encode(symbol, p3, v3)
            )
        );
        (, uint v4) = IGovernableLiquidityPool(pool).queryBuy(symbol, false);

        Assert.equal(v4, 0, "volume after selling");
    }
}