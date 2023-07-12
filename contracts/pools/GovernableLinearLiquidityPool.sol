pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./GovernableLiquidityPoolV2.sol";

contract GovernableLinearLiquidityPool is GovernableLiquidityPoolV2 {
    constructor(string memory _nm, string memory _sb, address _deployAddr, bool _onlyMintToOwner, address _owner)
        GovernableLiquidityPoolV2(_nm, _sb, _deployAddr, _onlyMintToOwner, _owner) public {}
    
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
        {
            address poolAddr = address(this);
            require(IOptionToken(_tk).writtenVolume(poolAddr).add(volume) <= param.bsStockSpread[0].toUint120(), "2 high vol");
            
            IOptionsExchange.OpenExposureInputs memory oEi;

            oEi.symbols = new string[](1);
            oEi.volume = new uint[](1);
            oEi.isShort = new bool[](1);
            oEi.isCovered = new bool[](1);
            oEi.poolAddrs = new address[](1);
            oEi.paymentTokens = new address[](1);


            oEi.symbols[0] = IOptionToken(_tk).symbol();
            oEi.volume[0] = volume;
            oEi.isShort[0] = true;
            oEi.poolAddrs[0] = poolAddr;
            //oEi.isCovered[0] = false; //expoliting default to save gas
            //oEi.paymentTokens[0] = address(0); //exploiting default to save gas


            exchange.openExposure(
                oEi,
                to
            );
        }
        
        require(calcFreeTradableBalance() > 0, "bal low");

    }

    /*
        TODO: 
            - FACTOR IN IF USER WANTS TO FILL THE TOTAL VOLUME THAT IT WILL MEAN THAT IT WILL BE THE MID MARKET PRICE?
    */

    function calcOptPrice(PricingParameters memory p, Operation op, uint poolPosBuy, uint poolPosSell)
        internal
        override
        view
        returns (uint price)
    {
        uint skew = calcSkewSpread(p, op, poolPosBuy, poolPosSell);
        uint spread = (op == Operation.BUY) ? p.bsStockSpread[2].add(fractionBase).sub(skew) : fractionBase.sub(p.bsStockSpread[2]).add(skew);
        price = interpolator.interpolate(
            getUdlPrice(p.udlFeed),
            p.t0,
            p.t1,
            p.x,
            p.y,
            spread
        );
    }

    function calcSkewSpread(PricingParameters memory p, Operation op, uint poolPosBuy, uint poolPosSell) private pure returns (uint skew) {
        uint skewBuy = (p.bsStockSpread[0] > 0) ? poolPosBuy.mul(p.bsStockSpread[2]).div(p.bsStockSpread[0]) : 0; //buy expo / max buy expo * spread
        uint skewSell = (p.bsStockSpread[1] > 0) ? poolPosSell.mul(p.bsStockSpread[2]).div(p.bsStockSpread[1]) : 0; //sell expo / max sell expo * spread

        skew =  (op == Operation.BUY) ? (
            (skewBuy > skewSell) ? 0 : skewSell //when pricing when someone wants to buy, if buy volume greater than sell volume, no discount, else discount back to mid
        ) : (
            (skewBuy > skewSell) ? skewBuy : 0 //when pricing when someone wants to sell, if buy volume greater than sell volume, discount back to mid, else no discount
        );
    }

    function calcVolume(
        string memory optSymbol,
        PricingParameters memory p,
        uint price,
        Operation op,
        uint poolPos
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
                calcFreeTradableBalance().mul(volumeBase).div(
                //calcFreeBalance().mul(volumeBase).div(
                    coll.sub(price.mul(r).div(fractionBase))
                ).add(poolPos);

                //balance in pool / (collateral per 1 option - premium recived per option)

        } else {

            uint bal = calcFreeTradableBalance();

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
                ).add(poolPos);

            uint balMulDiv = bal.mul(volumeBase).div(price);

            volume = MoreMath.min(
                MoreMath.max(
                    volume, 
                    balMulDiv
                ), 
                balMulDiv
            );
        }
    }
}