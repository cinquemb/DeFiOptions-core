pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./BaseCollateralManager.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IBaseHedgingManager.sol";
import "../utils/Convert.sol";

contract CollateralManager is BaseCollateralManager {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    function initialize(Deployer deployer) override internal {
        super.initialize(deployer);
    }


    function calcCollateralInternal(address owner, bool is_regular) override internal view returns (int) {
        // multi udl feed refs, need to make core accross all collateral models
        // do not normalize by volumeBase in internal calls for calcCollateralInternal
        
        int coll;
        (,address[] memory _tokens, uint[] memory _holding,, uint[] memory _uncovered, int[] memory _iv) = exchange.getBook(owner);

        address[] underlyings = new address[](tokens.length);

        for (uint i = 0; i < _tokens.length; i++) {

            address _tk = _tokens[i];
            IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);

            if (is_regular == false) {
                if (_uncovered[i] > _holding[i]) {
                    continue;
                }
            }

            coll = coll.add(
                _iv[i].mul(
                    int(_uncovered[i]).sub(int(_holding[i]))
                )
            ).add(int(calcCollateral(exchange.getExchangeFeeds(opt.udlFeed).upperVol, _uncovered[i], opt)));

            /*
                subtract off current exposure of position's underlying in dollars
            */

            address hmngr = ILiquidityPool(owner).getHedgingManager();
            if (settings.isAllowedHedgingManager(hmngr)) {
                address udlAddr = exchange.getUnderlyingAddr(opt);
                bool udlFound = foundUnderlying(udlAddr, underlyings);

                if (udlFound == false) {
                    int256 hedgeExposure = int256(
                        IBaseHedgingManager(hmngr).getHedgeExposure(
                            exchange.getUnderlyingAddr(opt)
                        )
                    );

                    coll = coll.add(
                        hedgeExposure
                    );

                    underlyings.push(udlAddr);
                }
                
            }
        }

        return coll;
    }

    function foundUnderlying(address udl, address[] udlArray) private view returns (bool){
        for (uint i; i < udlArray.length; i++) {
            if (udlArray[i] == udl) {
                return true;
            }
        }

        return false;
    }

    function calcCollateral(
        IOptionsExchange.OptionData calldata opt,
        uint volume
    ) override external view returns (uint)
    {
        IOptionsExchange.FeedData memory fd = exchange.getExchangeFeeds(opt.udlFeed);
        if (fd.lowerVol == 0 || fd.upperVol == 0) {
            fd = exchange.getFeedData(opt.udlFeed);
        }

        int coll = calcIntrinsicValue(opt).mul(int(volume)).add(
            int(calcCollateral(fd.upperVol, volume, opt))
        ).div(int(_volumeBase));

        if (opt._type == IOptionsExchange.OptionType.PUT) {
            int max = int(uint(opt.strike).mul(volume).div(_volumeBase));
            coll = MoreMath.min(coll, max);
        }

        return coll > 0 ? uint(coll) : 0;
    }

    function calcDelta(
        IOptionsExchange.OptionData calldata opt,
        uint volume
    ) override external view returns (int256){
        /* 
            - rfr == 0% assumption
            - (1 / (sigma * sqrt(T - t))) * (ln(S/k) + (((sigma**2) / 2) * ((T-t)))) == d1
                - underlying price S {\displaystyle S\,} S \, ,
                - strike price K {\displaystyle K\,} K \, ,
        */

        // using exchange 90 day window
        uint256 sigma = feed.getDailyVolatility(settings.getVolatilityPeriod());
        uint256 price_div_strike = exchange.getUdlPrice(opt).div(opt.strike);
        uint256 dt = opt.maturity.sub(settings.exchangeTime());


        //18 decimals to 128 decimals
        uint256 price_div_strike_128 = Convert.formatValue(price_div_strike, 128, 18);
        int256 ln_price_div_strike_128 = MoreMath.ln(price_div_strike_128);
        //128 decimals  to 18 decimals
        int256 ln_price_div_strike = Convert.formatValue(ln_price_div_strike_128, 18, 128);


        int256 d1 = ln_price_div_strike.add(
            ((sigma.pow(2)).div(2)).mul(dt)
        ).div(
            int256(sigma.mul(MoreMath.sqrt(dt)))
        )
        int256 delta;

        if (opt._type == IOptionsExchange.OptionType.PUT) {
            // -1 * norm_cdf(-d1) == put_delta
            delta = MoreMath.cumulativeDistributionFunction(d1.mul(-1)).mul(-1);
        
        } else {
            // norm_cdf(d1) == call_delta
            delta = MoreMath.cumulativeDistributionFunction(d1);
        }

        returns delta.mul(100).mul(volume);
    }
}