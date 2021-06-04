pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../governance/ProtocolSettings.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/LiquidityPool.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IOptionsExchange.sol";
import "../utils/SafeCast.sol";

contract CollateralManager is ManagedContract {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;
    
    ProtocolSettings private settings;
    ICreditProvider private creditProvider;
    IOptionsExchange private exchange;

    uint private _volumeBase;
    uint private timeBase;
    uint private sqrtTimeBase;

    function initialize(Deployer deployer) override internal {

        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));

        _volumeBase = 1e18;
        timeBase = 1e18;
        sqrtTimeBase = 1e9;
    }

    function collateralSkew() public view returns (int) {
        /*
            This allows the exchange to split any excess credit balance (due to debt) onto any new deposits while still holding debt balance for an individual account 
                OR
            split any excess stablecoin balance (due to more collected from debt than debt outstanding) to discount any new deposits()

            TODO: Combine multiple getters to save gas?
        */
        int totalStableCoinBalance = int(creditProvider.totalTokenStock()); // stable coin balance
        int totalCreditBalance = int(creditProvider.getTotalBalance()); // credit balance
        int totalOwners = int(creditProvider.getTotalOwners()).add(1);
        int skew = totalCreditBalance.sub(totalStableCoinBalance);

        // try to split between (total unique non zero balances on exchange / 2) if short stable coins
        if (totalCreditBalance >= totalStableCoinBalance) {
            return skew.div(totalOwners).mul(2);
        } else {
            return skew.div(totalOwners);
        }   
    }

    function calcExpectedPayout(address owner) external view returns (int payout) {

        (,address[] memory _book, uint[] memory _holding, uint[] memory _written, int[] memory _iv) = exchange.getBook(owner);

        for (uint i = 0; i < _book.length; i++) {
            payout = payout.add(
                _iv[i].mul(
                    int(_holding[i]).sub(int(_written[i]))
                )
            );
        }

        payout = payout.div(int(_volumeBase));
    }

    function calcCollateral(address owner, bool is_regular) public view returns (uint) {
        
        int coll;
        (,address[] memory _book, uint[] memory _holding, uint[] memory _written, int[] memory _iv) = exchange.getBook(owner);

        for (uint i = 0; i < _book.length; i++) {

            address _tk = _book[i];
            IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);

            if (is_regular == false) {
                if (_written[i] > _holding[i]) {
                    continue;
                }
            }

            coll = coll.add(
                _iv[i].mul(
                    int(_written[i]).sub(int(_holding[i]))
                )
            ).add(int(calcCollateral(exchange.getExchangeFeeds(opt.udlFeed).upperVol, _written[i], opt)));
        }

        // add split excess (could raise or lower collateral requirements)
        coll = coll.add(collateralSkew());

        coll = coll.div(int(_volumeBase));

        if (is_regular == false) {
            return uint(coll);
        }

        if (coll < 0)
            return 0;
        return uint(coll);
    }

    function calcLiquidationVolume(
        address owner,
        IOptionsExchange.OptionData memory opt,
        IOptionsExchange.FeedData memory fd,
        uint written
    )
        public
        view
        returns (uint volume)
    {    
        uint bal = creditProvider.balanceOf(owner);
        uint coll = exchange.calcCollateral(owner, true);
        require(coll > bal, "unfit for liquidation");

        volume = coll.sub(bal).mul(_volumeBase).mul(written).div(
            calcCollateral(
                uint(fd.upperVol).sub(uint(fd.lowerVol)),
                written,
                opt
            )
        );

        volume = MoreMath.min(volume, written);
    }

    function calcLiquidationValue(
        IOptionsExchange.OptionData memory opt,
        uint vol,
        uint written,
        uint volume,
        uint iv
    )
        public
        view
        returns (uint value)
    {    
        value = calcCollateral(vol, written, opt).add(iv).mul(volume).div(written);
    }

    function calcIntrinsicValue(IOptionsExchange.OptionData memory opt) public view returns (int value) {
        
        int udlPrice = exchange.getUdlPrice(opt);
        int strike = int(opt.strike);

        if (opt._type == IOptionsExchange.OptionType.CALL) {
            value = MoreMath.max(0, udlPrice.sub(strike));
        } else if (opt._type == IOptionsExchange.OptionType.PUT) {
            value = MoreMath.max(0, strike.sub(udlPrice));
        }
    }

    function calcCollateral(
        IOptionsExchange.OptionData calldata opt,
        uint volume
    )
        external
        view
        returns (uint)
    {
        IOptionsExchange.FeedData memory fd = exchange.getExchangeFeeds(opt.udlFeed);
        if (fd.lowerVol == 0 || fd.upperVol == 0) {
            fd = exchange.getFeedData(opt.udlFeed);
        }

        int coll = calcIntrinsicValue(opt).mul(int(volume)).add(
            int(calcCollateral(fd.upperVol, volume, opt))
        ).div(int(_volumeBase));

        return coll > 0 ? uint(coll) : 0;
    }
    
    function calcCollateral(uint vol, uint volume, IOptionsExchange.OptionData memory opt) internal view returns (uint) {
        
        return (vol.mul(volume).mul(
            MoreMath.sqrt(daysToMaturity(opt)))
        ).div(sqrtTimeBase);
    }

    function daysToMaturity(IOptionsExchange.OptionData memory opt) private view returns (uint d) {
        
        uint _now = exchange.getUdlNow(opt);
        if (opt.maturity > _now) {
            d = (timeBase.mul(uint(opt.maturity).sub(uint(_now)))).div(1 days);
        } else {
            d = 0;
        }
    }
}