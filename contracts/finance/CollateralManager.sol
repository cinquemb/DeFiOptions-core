pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./BaseCollateralManager.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IBaseHedgingManager";

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
                subtract off current delta of exposure of position in dollars
            */

            address hmngr = ILiquidityPool(owner).getHedgingManager();
            if (settings.isAllowedHedgingManager(hmngr)) {
                int delta = calcDelta(opt, _uncovered[i]);

                if (delta < 0) {
                    coll = coll.add(
                        delta.mul(
                            100
                        ).mul(
                            _uncovered[i]
                        ).mul(
                            exchnage.getUdlPrice(opt)
                        ).div(
                            IBaseHedgingManager(hmngr).getHedgeExposure(
                                exchange.getUnderlyingAddr(opt)
                            )
                        )
                    )
                } else {
                    coll = coll.sub(
                        delta.mul(
                            100
                        ).mul(
                            _uncovered[i]
                        ).mul(
                            exchnage.getUdlPrice(opt)
                        ).div(
                            IBaseHedgingManager(hmngr).getHedgeExposure(
                                exchange.getUnderlyingAddr(opt)
                            )
                        )
                    )
                }   
            }
        }

        return coll;
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
    ) public view returns (int){

    }
}