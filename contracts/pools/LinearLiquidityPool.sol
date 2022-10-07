pragma experimental ABIEncoderV2;
pragma solidity >=0.6.0;

import "./LinearInterpolator.sol";
import "./LiquidityPool.sol";

contract LinearLiquidityPool is LiquidityPool {
    
    LinearInterpolator private interpolator;

    string private constant _name = "Linear Liquidity Pool Redeemable Token";
    string private constant _symbol = "LLPTK";

    constructor() LiquidityPool(_name) public {
        
    }

    function initialize(Deployer deployer) override internal {

        super.initialize(deployer);
        interpolator = LinearInterpolator(deployer.getContractAddress("LinearInterpolator"));
    }

    function name() override external view returns (string memory) {
        return _name;
    }

    function symbol() override external view returns (string memory) {
        return _symbol;
    }

    function writeOptions(
        IOptionToken tk,
        PricingParameters memory param,
        uint volume,
        address to
    )
        internal
        override
    {
        require(tk.writtenVolume(address(this)).add(volume) <= param.buyStock, "excessive volume");

        IOptionsExchange.OpenExposureInputs memory oEi;
        
        oEi.symbols[0] = tk.symbol();
        oEi.volume[0] = volume;
        oEi.isShort[0] = true;
        oEi.isCovered[0] = false;
        oEi.poolAddrs[0] = address(this);
        oEi.paymentTokens[0] = address(0);

        exchange.openExposure(
            oEi,
            to
        );
        
        require(calcFreeBalance() > 0, "pool balance too low");
    }

    function calcOptPrice(PricingParameters memory p, Operation op)
        internal
        override
        view
        returns (uint)
    {
        return interpolator.interpolate(
            getUdlPrice(p.udlFeed),
            p.t0,
            p.t1,
            p.x,
            p.y,
            op == Operation.BUY ? spread.add(fractionBase) : fractionBase.sub(spread)
        );
    }

    function calcVolume(
        string memory optSymbol,
        PricingParameters memory p,
        uint price,
        Operation op
    )
        internal
        override
        view
        returns (uint volume)
    {
        uint r = fractionBase.sub(reserveRatio);

        uint coll = exchange.calcCollateral(
            p.udlFeed,
            volumeBase,
            p.optType,
            p.strike,
            p.maturity
        );

        if (op == Operation.BUY) {

            volume = coll <= price ? uint(-1) :
                calcFreeBalance().mul(volumeBase).div(
                    coll.sub(price.mul(r).div(fractionBase))
                );

        } else {

            uint bal = exchange.balanceOf(address(this));

            uint poolColl = exchange.collateral(address(this));

            uint writtenColl = IOptionToken(
                exchange.resolveToken(optSymbol)
            ).writtenVolume(address(this)).mul(coll);

            poolColl = poolColl > writtenColl ? poolColl.sub(writtenColl) : 0;
            
            uint iv = uint(exchange.calcIntrinsicValue(
                p.udlFeed,
                p.optType,
                p.strike,
                p.maturity
            ));

            volume = price <= iv ? uint(-1) :
                bal.sub(poolColl.mul(fractionBase).div(r)).mul(volumeBase).div(
                    price.sub(iv)
                );

            volume = MoreMath.max(
                volume, 
                bal.mul(volumeBase).div(price)
            );

            volume = MoreMath.min(
                volume, 
                bal.mul(volumeBase).div(price)
            );
        }
    }
}