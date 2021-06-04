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
import "./OptionToken.sol";

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

    event LiquidateEarly(
        address indexed token,
        address indexed sender,
        address indexed onwer,
        uint volume
    );

    event LiquidateExpired(
        address indexed token,
        address indexed sender,
        address indexed onwer,
        uint volume
    );

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
        private
        view
        returns (uint volume)
    {    
        uint bal = creditProvider.balanceOf(owner);
        uint coll = calcCollateral(owner, true);
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
        private
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

    function liquidateExpired(address _tk, address[] calldata owners) external {

        IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);
        OptionToken tk = OptionToken(_tk);
        require(getUdlNow(opt) >= opt.maturity, "option not expired");
        uint iv = uint(calcIntrinsicValue(opt));

        for (uint i = 0; i < owners.length; i++) {
            liquidateOptions(owners[i], opt, tk, true, iv);
        }
    }

    function liquidateOptions(address _tk, address owner) external returns (uint value) {
        
        IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);
        require(opt.udlFeed != address(0), "invalid token");

        OptionToken tk = OptionToken(_tk);
        require(tk.writtenVolume(owner) > 0, "invalid owner");

        bool isExpired = getUdlNow(opt) >= opt.maturity;
        uint iv = uint(calcIntrinsicValue(opt));
        
        value = liquidateOptions(owner, opt, tk, isExpired, iv);
    }

    function liquidateOptions(
        address owner,
        IOptionsExchange.OptionData memory opt,
        OptionToken tk,
        bool isExpired,
        uint iv
    )
        private
        returns (uint value)
    {
        uint written = tk.writtenVolume(owner);
        iv = iv.mul(written);

        if (isExpired) {
            value = liquidateAfterMaturity(owner, tk, written, iv);
            emit LiquidateExpired(address(tk), msg.sender, owner, written);
        } else {
            require(written > 0, "invalid volume");
            value = liquidateBeforeMaturity(owner, opt, tk, written, iv);
        }
    }

    function liquidateAfterMaturity(
        address owner,
        OptionToken tk,
        uint written,
        uint iv
    )
        private
        returns (uint value)
    {
        if (iv > 0) {
            value = iv.div(_volumeBase);
            creditProvider.processPayment(owner, address(tk), value);
        }

        if (written > 0) {
            tk.burn(owner, written);
        }
    }

    function liquidateBeforeMaturity(
        address owner,
        IOptionsExchange.OptionData memory opt,
        OptionToken tk,
        uint written,
        uint iv
    )
        private
        returns (uint value)
    {
        IOptionsExchange.FeedData memory fd = exchange.getExchangeFeeds(opt.udlFeed);


        uint volume = calcLiquidationVolume(owner, opt, fd, written);
        value = calcLiquidationValue(opt, fd.lowerVol, written, volume, iv)
            .div(_volumeBase);

        /* TODO:
            should be incentivized, i.e. compound gives 5% of collateral to liquidator 
            could be done in multistep where 
                - the first time triggers a margin call event for the owner (how to incentivize? 5% in credit tokens?)
                - sencond step triggers the actual liquidation (incentivized, 5% of collateral liquidated)
        */

        
        creditProvider.processPayment(owner, address(tk), value);

        if (volume > 0) {
            tk.burn(owner, volume);
        }

        emit LiquidateEarly(address(tk), msg.sender, owner, volume);
    }

    function daysToMaturity(IOptionsExchange.OptionData memory opt) private view returns (uint d) {
        uint _now = getUdlNow(opt);
        if (opt.maturity > _now) {
            d = (timeBase.mul(uint(opt.maturity).sub(uint(_now)))).div(1 days);
        } else {
            d = 0;
        }
    }

    function getUdlNow(IOptionsExchange.OptionData memory opt) private view returns (uint timestamp) {
        (timestamp,) = UnderlyingFeed(opt.udlFeed).getLatestPrice();
    }
}