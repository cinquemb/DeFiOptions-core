pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./GovernableLiquidityPoolV2.sol";

contract GovernableLinearLiquidityPool is GovernableLiquidityPoolV2 {
    constructor(string memory _nm, string memory _sb, address _deployAddr)
        GovernableLiquidityPoolV2(_nm, _sb, _deployAddr) public {}
    
    function name() override external view returns (string memory) {
        return string(abi.encodePacked(_name_prefix, _name));
    }

    function symbol() override external view returns (string memory) {

        return string(abi.encodePacked(_symbol_prefix, _symbol));
    }

    function writeOptions(
        address _tk,
        PricingParameters memory param,
        uint volume,
        address to
    )
        internal
        override
    {
        require(IOptionToken(_tk).writtenVolume(address(this)).add(volume) <= param.bsStockSpread[0].toUint120(), "excessive volume");
        require(calcFreeBalance() > 0, "pool balance too low");
        
        IOptionsExchange.OpenExposureInputs memory oEi;
        
        oEi.symbols[0] = IOptionToken(_tk).symbol();
        oEi.volume[0] = volume;
        oEi.isShort[0] = true;
        oEi.isCovered[0] = false;
        oEi.poolAddrs[0] = address(this);
        oEi.paymentTokens[0] = address(0);

        exchange.openExposure(
            oEi,
            to
        );
        
    }

    function calcOptPrice(PricingParameters memory p, Operation op)
        internal
        override
        view
        returns (uint price)
    {
        price = interpolator.interpolate(
            getUdlPrice(p.udlFeed),
            p.t0,
            p.t1,
            p.x,
            p.y,
            (op == Operation.BUY) ? p.bsStockSpread[2].add(fractionBase) : fractionBase.sub(p.bsStockSpread[2])
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