pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./BaseCollateralManager.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/IBaseHedgingManager.sol";
import "../utils/Convert.sol";

contract CollateralManager is BaseCollateralManager {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    struct CollateralData {
        address udlAddr;
        address hmngr;
        bool udlFound;
        int coll;
    }

    function initialize(Deployer deployer) override internal {
        super.initialize(deployer);
    }


    function calcCollateralInternal(address owner, bool is_regular) override internal view returns (int) {
        // multi udl feed refs, need to make core accross all collateral models
        // do not normalize by volumeBase in internal calls for calcCollateralInternal
        

        CollateralData memory cData;
        (,address[] memory _tokens, uint[] memory _holding,, uint[] memory _uncovered, int[] memory _iv) = exchange.getBook(owner);

        address[] memory underlyings = new address[](_tokens.length);

        for (uint i = 0; i < _tokens.length; i++) {
            IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tokens[i]);

            if (is_regular == false) {
                if (_uncovered[i] > _holding[i]) {
                    continue;
                }
            }

            cData.coll = cData.coll.add(
                _iv[i].mul(
                    int(_uncovered[i]).sub(int(_holding[i]))
                )
            ).add(
                int(
                    calcCollateral(
                        exchange.getExchangeFeeds(opt.udlFeed).upperVol,
                        _uncovered[i],
                        opt
                    )
                )
            );

            /*
                subtract off current exposure of position's underlying in dollars
                //GET FEEDBACK ON HOW TO FACTOR IN HEDGE VALUE FOR COLLATERAL
            */

            cData.hmngr = IGovernableLiquidityPool(owner).getHedgingManager();
            if (settings.isAllowedHedgingManager(cData.hmngr)) {
                cData.udlAddr = UnderlyingFeed(opt.udlFeed).getUnderlyingAddr();
                cData.udlFound = foundUnderlying(cData.udlAddr, underlyings);

                if (cData.udlFound == false) {
                    {
                        cData.coll = cData.coll.sub(
                            int256(
                                MoreMath.abs(
                                    int256(
                                        IBaseHedgingManager(cData.hmngr).getHedgeExposure(
                                           cData.udlAddr,
                                           owner
                                        )
                                    )
                                )
                            )
                        );
                    }

                    underlyings[i] = cData.udlAddr;
                }
                
            }
        }

        return cData.coll;
    }

    function foundUnderlying(address udl, address[] memory udlArray) private view returns (bool){
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
    ) external view returns (int256){
        /* 
            - rfr == 0% assumption
            - (1 / (sigma * sqrt(T - t))) * (ln(S/k) + (((sigma**2) / 2) * ((T-t)))) == d1
                - underlying price S
                - strike price K
        */

        // using exchange 90 day window
        uint256 sigma = UnderlyingFeed(opt.udlFeed).getDailyVolatility(settings.getVolatilityPeriod());
        uint256 price_div_strike = uint256(exchange.getUdlPrice(opt).div(opt.strike));
        uint256 dt = uint256(opt.maturity).sub(settings.exchangeTime());


        //18 decimals to 128 decimals
        uint256 price_div_strike_128 = Convert.formatValue(price_div_strike, 128, 18);
        int256 ln_price_div_strike_128 = MoreMath.ln(price_div_strike_128);
        //128 decimals  to 18 decimals
        int256 ln_price_div_strike = Convert.formatValue(ln_price_div_strike_128, 18, 128);


        int256 d1 = ln_price_div_strike.add(
            int256(((MoreMath.pow(sigma, 2)).div(2)).mul(dt))
        ).div(
            int256(sigma.mul(MoreMath.sqrt(dt)))
        );
        int256 delta;

        if (opt._type == IOptionsExchange.OptionType.PUT) {
            // -1 * norm_cdf(-d1) == put_delta
            delta = MoreMath.cumulativeDistributionFunction(d1.mul(-1)).mul(-1);
        
        } else {
            // norm_cdf(d1) == call_delta
            delta = MoreMath.cumulativeDistributionFunction(d1);
        }

        return delta.mul(100).mul(int256(volume));
    }

    function borrowTokensByPreference(address to, uint value, address[] calldata tokensInOrder, uint[] calldata amountsOutInOrder) external {
        creditProvider.borrowTokensByPreference(to, value, tokensInOrder, amountsOutInOrder);
    }
}