pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../deployment/Deployer.sol";
import "../../deployment/ManagedContract.sol";
import "../../interfaces/IProtocolSettings.sol";
import "../../interfaces/UnderlyingFeed.sol";
import "../../interfaces/IGovernableLiquidityPool.sol";
import "../../interfaces/ICreditProvider.sol";
import "../../interfaces/IOptionsExchange.sol";
import "../../interfaces/IOptionToken.sol";
import "../../interfaces/IUnderlyingVault.sol";
import "../../interfaces/IUnderlyingCreditProvider.sol";
import "../../interfaces/IBaseCollateralManager.sol";
import "../../interfaces/IUniswapV2Router01.sol";
import "../../utils/SafeCast.sol";
import "../../utils/MoreMath.sol";
import "../../utils/Decimal.sol";
import "../../utils/Convert.sol";
import "../../utils/SafeERC20.sol";

abstract contract BaseCollateralManager is ManagedContract, IBaseCollateralManager {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;
    using Decimal for Decimal.D256;
    using SafeERC20 for IERC20_2;

    
    IUnderlyingVault private vault;
    IProtocolSettings internal settings;
    ICreditProvider internal creditProvider;
    IOptionsExchange internal exchange;

    uint private timeBase;
    uint private sqrtTimeBase;
    uint private collateralCallPeriod;
    uint internal _volumeBase;

    mapping(address => mapping(address => uint256)) private writerCollateralCall;

    event LiquidateEarly(
        address indexed token,
        address indexed sender,
        address indexed onwer,
        uint volume
    );

    event CollateralCall(
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

    event DebtSwap(
        address indexed tokenA,
        address indexed tokenB,
        uint volume
    );

    function initialize(Deployer deployer) virtual override internal {

        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
        vault = IUnderlyingVault(deployer.getContractAddress("UnderlyingVault"));

        _volumeBase = 1e18;
        timeBase = 1e18;
        sqrtTimeBase = 1e9;
        collateralCallPeriod = 1 days;
    }

    function collateralSkew(address underlyingFeed) private view returns (int) {
        // core across all collateral models
        /*
            This allows the exchange to split any excess credit balance (due to debt) onto any new deposits while still holding debt balance for an individual account;
        */

        address underlying = UnderlyingFeed(underlyingFeed).getUnderlyingAddr();
        if (underlying == address(0)) {
            return 0;
        }
        
        (,int answer) = UnderlyingFeed(underlyingFeed).getLatestPrice();
        address udlCdtp = vault.getUnderlyingCreditProvider(underlying);
        int totalUnderlyingBalance = int(IUnderlyingCreditProvider(udlCdtp).totalTokenStock()); // underlying token balance
        int totalUnderlyingCreditBalance = int(IUnderlyingCreditProvider(udlCdtp).getTotalBalance()); // credit balance
        int totalOwners = int(creditProvider.getTotalOwners()).add(1);
        //need to multiple by latest price of asset to normalize into exchange balance amount
        int skew = totalUnderlyingCreditBalance.sub(totalUnderlyingBalance).mul(answer).div(int(_volumeBase));

        // try to split between if short underlying tokens
        return skew.div(totalOwners);  
    }

    function collateralSkewForPositionUnderlying(int coll, address underlyingFeed) internal view returns (int) {
        // core across all collateral models, only apply residual
        int modColl;
        int skew = collateralSkew(underlyingFeed);
        Decimal.D256 memory skewPct;
        if (skew != 0){
            skewPct = Decimal.ratio(uint(coll), MoreMath.abs(skew));
        } else {
            skewPct = Decimal.zero();
        }

        if (skewPct.greaterThanOrEqualTo(Decimal.one())) {
            modColl = skew;
        } else {
            // shortag per addr exceeds underlying collateral reqs, only add percentage increase of underlying collateral reqs, never reduce collateral requirements for positions covered by underlying

            int modSkew = int(Decimal.mul(skewPct, uint(coll)).asUint256());
            modColl = (skew >= 0) ? modSkew : 0;
        }

        return modColl;
    }

    function collateralSkew() private view returns (int) {
        // core across all collateral models
        /*
            This allows the exchange to split any excess credit balance (due to debt) onto any new deposits while still holding debt balance for an individual account 
                OR
            split any excess stablecoin balance (due to more collected from debt than debt outstanding) to discount any new deposits()
        */
        int totalStableCoinBalance = int(creditProvider.totalTokenStock()); // stable coin balance
        int totalCreditBalance = int(creditProvider.getTotalBalance()); // credit balance
        int totalOwners = int(creditProvider.getTotalOwners()).add(1);
        int skew = totalCreditBalance.sub(totalStableCoinBalance);

        // try to split between if short stable coins
        return skew.div(totalOwners);  
    }

    function collateralSkewForPosition(int coll) internal view returns (int) {
        // core across all collateral models
        int modColl;
        int skew = collateralSkew();
        Decimal.D256 memory skewPct;
        if (skew != 0){
            skewPct = Decimal.ratio(uint(coll), MoreMath.abs(skew));
        } else {
            skewPct = Decimal.zero();
        }

        if (skewPct.greaterThanOrEqualTo(Decimal.one())) {
            modColl = coll.add(skew);
        } else {
            // shortage/surplus per addr exceeds underlying collateral reqs, only add/sub percentage increase of underlying collateral reqs

            int modSkew = int(Decimal.mul(skewPct, uint(coll)).asUint256());
            modColl = (skew >= 0) ? coll.add(modSkew) : coll.sub(modSkew);
        }

        return modColl;
    }

    function calcExpectedPayout(address owner) override external view returns (int payout) {
        // multi udl feed refs, need to make core accross all collateral models
        (,address[] memory _tokens, uint[] memory _holding, uint[] memory _written,, int[] memory _iv,) = exchange.getBook(owner);

        for (uint i = 0; i < _tokens.length; i++) {
            int price = queryPoolPrice(owner, IOptionToken(_tokens[i]).name());
            payout = payout.add(
                (price != 0 ? price : _iv[i]).mul(
                    int(_holding[i]).sub(int(_written[i]))
                )
            );
        }

        payout = payout.div(int(_volumeBase));
    }

    function calcCollateralInternal(address owner, bool is_regular) virtual internal view returns (int);

    function calcNetCollateralInternal(address[] memory _tokens, uint[] memory _uncovered, uint[] memory _holding, bool is_regular)  virtual internal view returns (int);

    function calcLiquidationVolume(
        address owner,
        IOptionsExchange.OptionData memory opt,
        address _tk,
        IOptionsExchange.FeedData memory fd,
        uint written
    )
        private
        returns (uint volume)
    {    
        uint bal = creditProvider.balanceOf(owner);
        uint coll = calcCollateral(owner, true);

        if (coll > bal) {
            if (writerCollateralCall[owner][_tk] != 0) {
                // cancel collateral call
                writerCollateralCall[owner][_tk] = 0;
            }
        }
        require(coll > bal, "Collateral Manager: unfit for liquidation");
        
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

    function calcIntrinsicValue(IOptionsExchange.OptionData memory opt) override public view returns (int value) {
        
        int udlPrice = getUdlPrice(opt);
        int strike = int(opt.strike);

        if (opt._type == IOptionsExchange.OptionType.CALL) {
            value = MoreMath.max(0, udlPrice.sub(strike));
        } else if (opt._type == IOptionsExchange.OptionType.PUT) {
            value = MoreMath.max(0, strike.sub(udlPrice));
        }
    }

    function queryPoolPrice(
        address poolAddr,
        string memory symbol
    )
        override public
        view
        returns (int)
    {
        uint price = 0;
        IGovernableLiquidityPool pool = IGovernableLiquidityPool(poolAddr);
        

        try pool.queryBuy(symbol, true) returns (uint _buyPrice, uint) {
            price = price.add(_buyPrice);
        } catch (bytes memory /*lowLevelData*/) {
            return 0;
        }

        try pool.queryBuy(symbol, false) returns (uint _sellPrice, uint) {
            price = price.add(_sellPrice);
        } catch (bytes memory /*lowLevelData*/) {
            return 0;
        }

        return int(price).div(2);
    }

    function getFeedData(address udlFeed) internal view returns (IOptionsExchange.FeedData memory fd) {
        UnderlyingFeed feed = UnderlyingFeed(udlFeed);

        uint vol = feed.getDailyVolatility(settings.getVolatilityPeriod());

        fd = IOptionsExchange.FeedData(
            feed.calcLowerVolatility(uint(vol)).toUint120(),
            feed.calcUpperVolatility(uint(vol)).toUint120()
        );
    }

    function calcCollateral(
        IOptionsExchange.OptionData calldata opt,
        uint volume
    ) override virtual external view returns (uint);
    
    function calcCollateral(uint vol, uint volume, IOptionsExchange.OptionData memory opt) internal view returns (uint) {
        
        return (vol.mul(volume).mul(
            MoreMath.sqrt(daysToMaturity(opt)))
        ).div(sqrtTimeBase);
    }

    function liquidateExpired(address _tk, address[] calldata owners) override external {

        IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);
        IOptionToken tk = IOptionToken(_tk);
        require(getUdlNow(opt) >= opt.maturity, "Collateral Manager: option not expired");
        uint iv = uint(calcIntrinsicValue(opt));

        for (uint i = 0; i < owners.length; i++) {
            liquidateOptions(owners[i], opt, tk, true, iv);
        }
    }

    function liquidateOptions(address _tk, address owner) override external returns (uint value) {
        
        IOptionsExchange.OptionData memory opt = exchange.getOptionData(_tk);
        require(opt.udlFeed != address(0), "invalid token");

        IOptionToken tk = IOptionToken(_tk);
        require(tk.writtenVolume(owner) > 0, "Collateral Manager: invalid owner");

        bool isExpired = getUdlNow(opt) >= opt.maturity;
        uint iv = uint(calcIntrinsicValue(opt));
        
        value = liquidateOptions(owner, opt, tk, isExpired, iv);
    }

    function liquidateOptions(
        address owner,
        IOptionsExchange.OptionData memory opt,
        IOptionToken tk,
        bool isExpired,
        uint iv
    )
        private
        returns (uint value)
    {
        uint written = isExpired ?
            tk.writtenVolume(owner) :
            tk.uncoveredVolume(owner);
        iv = iv.mul(written);

        if (isExpired) {
            value = liquidateAfterMaturity(owner, tk, opt.udlFeed, written, iv);
            emit LiquidateExpired(address(tk), msg.sender, owner, written);
        } else {
            require(written > 0, "Collateral Manager: invalid volume");
            value = liquidateBeforeMaturity(owner, opt, tk, written, iv);
        }
    }

    function liquidateAfterMaturity(
        address owner,
        IOptionToken tk,
        address feed,
        uint written,
        uint iv
    )
        private
        returns (uint value)
    {

        // if borrowed liquidty was used to write options need to debit it from pool addr
        creditProvider.processIncentivizationPayment(msg.sender, settings.getBaseIncentivisation());
        creditProvider.nullOptionBorrowBalance(address(tk), owner);

        if (iv > 0) {
            value = iv.div(_volumeBase);
            vault.liquidate(owner, address(tk), feed, value);
            creditProvider.processPayment(owner, address(tk), value);
        }

        vault.release(owner, address(tk), feed, uint(-1));

        if (written > 0) {
            exchange.burn(owner, written, address(tk));
        }
    }

    function liquidateBeforeMaturity(
        address owner,
        IOptionsExchange.OptionData memory opt,
        IOptionToken tk,
        uint written,
        uint iv
    )
        private
        returns (uint value)
    {
        IOptionsExchange.FeedData memory fd = getFeedData(opt.udlFeed);
        address tkAddr = address(tk);
        uint volume = calcLiquidationVolume(owner, opt, tkAddr, fd, written);
        value = calcLiquidationValue(opt, fd.lowerVol, written, volume, iv)
            .div(_volumeBase);

        uint now = settings.exchangeTime();
        bool nearMat = (opt.maturity > now) ? (uint256(opt.maturity).sub(now) < (60 * 60 * 24)) : true;

        if ((writerCollateralCall[owner][tkAddr] == 0) && (nearMat == false)) {
            // the first time triggers a margin call event for the owner (how to incentivize? 10$ in exchange credit)
            if (msg.sender != owner) {
                writerCollateralCall[owner][tkAddr] = now;
                creditProvider.processIncentivizationPayment(msg.sender, settings.getBaseIncentivisation());
                emit CollateralCall(tkAddr, msg.sender, owner, volume);
            }
        } else {
            if ((writerCollateralCall[owner][tkAddr] == 0) && (nearMat == true)) {
                //pass, liq right away
            } else {
                require(now.sub(writerCollateralCall[owner][tkAddr]) >= collateralCallPeriod, "Collateral Manager: active collateral call");
            }

            if (msg.sender != owner){
                // second step triggers the actual liquidation (incentivized, 5% of collateral liquidated in exchange creditbalance, owner gets charged 105%)
                uint256 creditingValue = value.mul(5).div(100);
                creditProvider.processPayment(owner, tkAddr, value.add(creditingValue));
                creditProvider.processIncentivizationPayment(address(settings), creditingValue);
                creditProvider.processIncentivizationPayment(msg.sender, settings.getBaseIncentivisation());


                if ((collateralSkew() <= 0) && (collateralSkew(opt.udlFeed) > 0)) {
                    //swap underlying debt for stablecoin debt
                    debtSwapInternal(opt.udlFeed, creditingValue);
                }
            }

            if (volume > 0) {
                exchange.burn(owner, volume, address(tk));
            }

            emit LiquidateEarly(tkAddr, msg.sender, owner, volume);
        }        
    }

    function calcCollateral(address owner, bool is_regular) override public view returns (uint) {     
        // takes custom collateral requirements and applies exchange level normalizations   
        int coll = calcCollateralInternal(owner, is_regular);
        return baseCalcCollateral(coll, is_regular);
    }

    function calcNetCollateral(address[] memory _tokens, uint[] memory _uncovered, uint[] memory _holding, bool is_regular) override public view returns (uint) {     
        // takes custom collateral requirements and applies exchange level normalizations on prospective positions
        int coll = calcNetCollateralInternal(_tokens, _uncovered, _holding, is_regular);
        return baseCalcCollateral(coll, is_regular);
    }

    function baseCalcCollateral(int coll, bool is_regular) private view returns (uint) {
        coll = collateralSkewForPosition(coll);
        coll = coll.div(int(_volumeBase));

        if (is_regular == false) {
            return uint(coll);
        }

        if (coll < 0)
            return 0;
        return uint(coll);
    }

    function debtSwap(address udlFeed, uint256 creditingValue) override external {
        require(msg.sender == address(settings), "non settings");
        debtSwapInternal(udlFeed,creditingValue);
    }

    function debtSwapInternal(address udlFeed, uint256 creditingValue) private {
        (, address _stablecoin) = settings.getSwapRouterInfo();
        (, int p) = UnderlyingFeed(udlFeed).getLatestPrice();
        address underlying = UnderlyingFeed(udlFeed).getUnderlyingAddr();

        address udlCdtp = vault.getUnderlyingCreditProvider(underlying);
        uint256 totalUnderlyingBalance = IUnderlyingCreditProvider(udlCdtp).totalTokenStock(); // underlying token balance
        uint256 totalUnderlyingCreditBalance = IUnderlyingCreditProvider(udlCdtp).getTotalBalance(); // credit balance

        //NEED TO DO THIS BEFORE CALLING `swapStablecoinForUnderlying` in order to make sure enough stables in udlCdtp
        address[] memory tokensInOrder = new address[](1);
        uint[] memory amountsOutInOrder = new uint[](1);
        tokensInOrder[0] = _stablecoin;
        amountsOutInOrder[0] = Convert.from18DecimalsBase(_stablecoin, creditingValue);
        creditProvider.grantTokens(address(udlCdtp), creditingValue, tokensInOrder, amountsOutInOrder);

        IUnderlyingCreditProvider(udlCdtp).swapStablecoinForUnderlying(
            udlCdtp,
            settings.getSwapPath(
                _stablecoin,
                underlying
            ),
            p,
            creditingValue, //how much stables we are willing to swap for underlying
            totalUnderlyingCreditBalance.sub(totalUnderlyingBalance)//how much we are short underlying
        );

        emit DebtSwap(_stablecoin, underlying, creditingValue);
    }

    function daysToMaturity(IOptionsExchange.OptionData memory opt) private view returns (uint d) {
        uint _now = getUdlNow(opt);
        if (opt.maturity > _now) {
            d = (timeBase.mul(uint(opt.maturity).sub(uint(_now)))).div(1 days);
        } else {
            d = 0;
        }
    }

    function getUdlPrice(IOptionsExchange.OptionData memory opt) internal view returns (int answer) {

        if (opt.maturity > settings.exchangeTime()) {
            (,answer) = UnderlyingFeed(opt.udlFeed).getLatestPrice();
        } else {
            (,answer) = UnderlyingFeed(opt.udlFeed).getPrice(opt.maturity);
        }
    }

    function getUdlNow(IOptionsExchange.OptionData memory opt) private view returns (uint timestamp) {
        (timestamp,) = UnderlyingFeed(opt.udlFeed).getLatestPrice();
    }
}