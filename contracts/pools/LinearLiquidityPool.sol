pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../interfaces/IInterpolator.sol";
import "./LiquidityPool.sol";

contract LinearLiquidityPool is LiquidityPool {
    
    constructor(string memory _nm, string memory _sb, address _ownerAddr, address _deployAddr)
        LiquidityPool(_nm, _sb, _ownerAddr, _deployAddr) public {
        Deployer deployer = Deployer(_deployAddr);
        interpolatorAddr = deployer.getContractAddress("Interpolator");
    }

    function name() override external view returns (string memory) {
        return string(abi.encodePacked(_name_prefix, _name));
    }

    function symbol() override external view returns (string memory) {

        return string(abi.encodePacked(_symbol_prefix, _symbol));
    }

    function writeOptions(
        OptionToken tk,
        PricingParameters memory param,
        uint volume,
        address to
    )
        internal
        override
    {
        uint _written = tk.writtenVolume(address(this));
        require(_written.add(volume) <= param.buyStock, "excessive volume");

        IOptionsExchange(exchangeAddr).writeOptions(
            param.udlFeed,
            volume,
            param.optType,
            param.strike,
            param.maturity,
            to
        );
        
        require(calcFreeBalance() > 0, "pool balance too low");
    }

    function calcOptPrice(PricingParameters memory p, Operation op)
        internal
        override
        view
        returns (uint price)
    {
        uint f = op == Operation.BUY ? spread.add(fractionBase) : fractionBase.sub(spread);
        int udlPrice = getUdlPrice(p.udlFeed);
        price = IInterpolator(interpolatorAddr).interpolate(udlPrice, p.t0, p.t1, p.x, p.y, f);
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
        uint fb = calcFreeBalance();
        uint r = fractionBase.sub(reserveRatio);

        uint coll = IOptionsExchange(exchangeAddr).calcCollateral(
            p.udlFeed,
            volumeBase,
            p.optType,
            p.strike,
            p.maturity
        );

        if (op == Operation.BUY) {

            volume = coll <= price ? uint(-1) :
                fb.mul(volumeBase).div(
                    coll.sub(price.mul(r).div(fractionBase))
                );

        } else {

            uint bal = IOptionsExchange(exchangeAddr).balanceOf(address(this));

            uint poolColl = IOptionsExchange(exchangeAddr).collateral(address(this));

            uint writtenColl = OptionToken(
                IOptionsExchange(exchangeAddr).resolveToken(optSymbol)
            ).writtenVolume(address(this)).mul(coll);

            poolColl = poolColl > writtenColl ? poolColl.sub(writtenColl) : 0;
            
            uint iv = uint(IOptionsExchange(exchangeAddr).calcIntrinsicValue(
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