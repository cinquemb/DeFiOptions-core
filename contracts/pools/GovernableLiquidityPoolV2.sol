pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/ManagedContract.sol";
import "../interfaces/IOptionToken.sol";
import "../interfaces/IProposal.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/IYieldTracker.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IProposalWrapper.sol";
import "../interfaces/IProposalManager.sol";
import "../interfaces/IInterpolator.sol";
import "../interfaces/IBaseHedgingManager.sol";
import "../finance/RedeemableToken.sol";
import "../utils/SafeERC20.sol";
import "../utils/SafeCast.sol";
import "../utils/MoreMath.sol";
import "../utils/SignedSafeMath.sol";

abstract contract GovernableLiquidityPoolV2 is ManagedContract, RedeemableToken, IGovernableLiquidityPool {

    using SafeERC20 for IERC20_2;
    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    string internal _name;
    string internal _symbol;
    string internal constant _symbol_prefix = "DODv2-LLPRTK-";
    string internal constant _name_prefix = "Linear Liquidity Pool Redeemable Token: ";

    IYieldTracker private tracker;
    IProtocolSettings private settings;
    IInterpolator internal interpolator;
    ICreditProvider private creditProvider;
    IProposalManager private proposalManager;

    mapping(string => PricingParameters) private parameters;
    mapping(string => mapping(uint => Range)) private ranges;

    uint public override maturity;
    uint public override withdrawFee;
    uint internal volumeBase = 1e18;
    uint internal reserveRatio;
    uint internal fractionBase;
    uint internal _leverageMultiplier;
    uint internal _hedgeThreshold;

    address private _hedgingManagerAddress;
    bool private onlyMintToOwner;
    
    string[] private optSymbols;

    constructor(string memory _nm, string memory _sb, address _deployAddr, bool _onlyMintToOwner, address _owner)
        ERC20(string(abi.encodePacked(_name_prefix, _nm)))
        public
    {    
        _symbol = _sb;
        _name = _nm;

        fractionBase = 1e9;
        exchange = IOptionsExchange(Deployer(_deployAddr).getContractAddress("OptionsExchange"));
        settings = IProtocolSettings(Deployer(_deployAddr).getContractAddress("ProtocolSettings"));
        creditProvider = ICreditProvider(Deployer(_deployAddr).getContractAddress("CreditProvider"));
        tracker = IYieldTracker(Deployer(_deployAddr).getContractAddress("YieldTracker"));
        interpolator = IInterpolator(Deployer(_deployAddr).getContractAddress("Interpolator"));
        proposalManager = IProposalManager(Deployer(_deployAddr).getContractAddress("ProposalsManager"));
        owner = _owner;
        onlyMintToOwner = _onlyMintToOwner;
    }

    function setParameters(
        uint _reserveRatio,
        uint _withdrawFee,
        uint _mt,
        uint _lm,
        address _hmngr,
        uint _ht
    )
        override external
    {
        ensureCaller();
        reserveRatio = _reserveRatio;
        withdrawFee = _withdrawFee;
        maturity = _mt;
        _leverageMultiplier = _lm;
        _hedgingManagerAddress = _hmngr;
        _hedgeThreshold = _ht;
    }

    function getHedgingManager() override public view returns (address) {
        return _hedgingManagerAddress;
    }

    function getHedgeNotionalThreshold() override external view returns (uint) {
        return _hedgeThreshold;
    }

    function getLeverage() override public view returns (uint) {
        return _leverageMultiplier;
    }

    function redeemAllowed() override public view returns (bool) {
        
        return block.timestamp >= maturity; //FOR DEPLOYMENTS
        //return settings.exchangeTime() >= maturity;//FOR TESTS
    }

    function yield(uint dt) override external view returns (uint) {
        return tracker.yield(address(this), dt);
    }
    
    function addSymbol(
        address udlFeed,
        uint strike,
        uint _mt,
        IOptionsExchange.OptionType optType,
        uint t0,
        uint t1,
        uint120[] calldata x,
        uint120[] calldata y,
        uint[3] calldata bsStockSpread
    )
        override external
    {
        ensureCaller();
        require(x.length > 0 && x.length.mul(2) == y.length && _mt < maturity, "bad x/y or _mt");

        string memory optSymbol = exchange.getOptionSymbol(
            IOptionsExchange.OptionData(udlFeed, optType, strike.toUint120(), _mt.toUint32())
        );

        if (parameters[optSymbol].x.length == 0) {
            optSymbols.push(optSymbol);
        }

        parameters[optSymbol] = PricingParameters(
            udlFeed,
            optType,
            strike.toUint120(),
            _mt.toUint32(),
            t0.toUint32(),
            t1.toUint32(),
            bsStockSpread,
            x,
            y
        );

        emit AddSymbol(optSymbol);
    }

    function setRange(string calldata optSymbol, Operation op, uint start, uint end) external {
        ensureCaller();
        ranges[optSymbol][uint(op)] = Range(start.toUint120(), end.toUint120());
    }

    function removeSymbol(string calldata optSymbol) external {
        require(parameters[optSymbol].maturity >= block.timestamp, "2 soon");        
        Arrays.removeItem(optSymbols, optSymbol);
    }

    function depositTokens(address to, address token, uint value) override public {

        if (onlyMintToOwner) {
            require(to == owner, "bad ownr");
        }

        (uint b0, int po) = getBalanceAndPayout();
        depositTokensInExchange(token, value);
        uint b1 = exchange.balanceOf(address(this));
        
        //tracker.push(int(b0).add(po), b1.sub(b0).toInt256());

        int expBal = po.add(int(b1));
        uint p = b1.sub(b0).mul(fractionBase).div(uint(expBal));

        uint b = 1e3;
        uint v = _totalSupply > 0 ?
            _totalSupply.mul(p).mul(b).div(fractionBase.sub(p)) : 
            uint(expBal).mul(b);
        v = MoreMath.round(v, b);

        addBalance(to, v);
        _totalSupply = _totalSupply.add(v);
        emitTransfer(address(0), to, v);
    }

    function withdraw(uint amount) override external {

        uint bal = balanceOf(msg.sender);
        require(bal >= amount, "low bal");

        uint val = valueOf(msg.sender).mul(amount).div(bal);
        uint discountedValue = val.mul(fractionBase.sub(withdrawFee)).div(fractionBase);
        uint freeBal = calcFreeBalance();

        if (freeBal > 0) {
            //(uint b0, int po) = getBalanceAndPayout();
            
            exchange.transferBalance(
                msg.sender, 
                (discountedValue <= freeBal) ? discountedValue : freeBal
            );
            
            /*tracker.push(
                int(b0).add(po), 
                -(((discountedValue <= freeBal) ? val : freeBal).toInt256())
            );*/
        }
        
        removeBalance(msg.sender, amount);
        _totalSupply = _totalSupply.sub(amount);
        emitTransfer(msg.sender, address(0), amount);
    }

    function calcFreeBalance() override public view returns (uint balance) {
        //used for pool deposits/withdrawls of pool tokens
        uint exBal = exchange.balanceOf(address(this));
        uint reserve = exBal.mul(reserveRatio).div(fractionBase);
        uint sp = exBal.sub(exchange.collateral(address(this)));
        balance = sp > reserve ? sp.sub(reserve) : 0;
    }

    function calcFreeTradableBalance() internal view returns (uint balance) {
        //used for calcing what traders can trade against
        uint exBal = settings.getPoolCreditTradeable(address(this));
        uint reserve = exBal.mul(reserveRatio).div(fractionBase);
        uint sp = exBal.sub(exchange.collateral(address(this)));
        balance = sp > reserve ? sp.sub(reserve) : 0;
    }

    function listSymbols() override external view returns (string memory available) {
        for (uint i = 0; i < optSymbols.length; i++) {
            if (bytes(available).length == 0) {
                available = optSymbols[i];
            } else {
                available = string(abi.encodePacked(available, "\n", optSymbols[i]));
            }
        }
    }

    function queryBuy(string memory optSymbol, bool isBuy)
        override
        public
        view
        returns (uint price, uint volume)
    {

        Operation op = (isBuy == true) ? Operation.BUY : Operation.SELL;

        PricingParameters memory param = parameters[optSymbol];
        address _tk = exchange.resolveToken(optSymbol);
        uint optBal = (op == Operation.SELL) ? IOptionToken(_tk).balanceOf(address(this)) : IOptionToken(_tk).writtenVolume(address(this));
        price = calcOptPrice(param, op, IOptionToken(_tk).balanceOf(address(this)), IOptionToken(_tk).writtenVolume(address(this)));
        volume = MoreMath.min(
            calcVolume(optSymbol, param, price, op, 0),
            (op == Operation.SELL) ? (
                (param.bsStockSpread[1] >= optBal) ? param.bsStockSpread[1].sub(optBal) : 0
            ) : (
            (param.bsStockSpread[0] >= optBal) ? param.bsStockSpread[0].sub(optBal) : 0
            )
        );
    }

    function buy(string memory optSymbol, uint price, uint volume, address token)
        override
        public
        returns (address _tk)
    {
        PricingParameters memory param;
        _tk = exchange.resolveToken(optSymbol);

        (price, param)  = validateOrder(volume, price, optSymbol, Operation.BUY, _tk);
        checkApproved(param.udlFeed);

        uint value = price.mul(volume).div(volumeBase);
        if (token != address(exchange)) {
            (uint tv, uint tb) = settings.getTokenRate(token);
            value = value.mul(tv).div(tb);
            depositTokensInExchange(token, value);
        } else {
            exchange.transferBalance(msg.sender, address(this), value);
        }


        if (volume > IOptionToken(_tk).balanceOf(address(this))) {
            // only credit the amount excess what is already available
            uint freeBal = calcFreeBalance();
            if (value > freeBal){
                creditProvider.borrowBuyLiquidity(address(this), value.sub(freeBal), _tk);
            }
            writeOptions(_tk, param, volume, msg.sender);
        } else {
            IOptionToken(_tk).transfer(msg.sender, volume);
        }

        hedge(param);

        emit Buy(_tk, msg.sender, price, volume);
    }

    function sell(
        string memory optSymbol,
        uint price,
        uint volume
    )
        override
        public
    {
        PricingParameters memory param;
        address _tk = exchange.resolveToken(optSymbol);
        (price, param) = validateOrder(volume, price, optSymbol, Operation.SELL, _tk);
        checkApproved(param.udlFeed);

        IOptionToken(_tk).transferFrom(msg.sender, address(this), volume);
        
        uint _written = IOptionToken(_tk).writtenVolume(address(this));
        if (_written > 0) {
            IOptionToken(_tk).burn(
                MoreMath.min(_written, volume)
            );
        }

        uint value = price.mul(volume).div(volumeBase);
        uint freeBal = calcFreeBalance();
        if (freeBal < value) {
            // only credit the amount excess what is already available, will fail if hedging manager not approved
            creditProvider.borrowSellLiquidity(address(this), value.sub(freeBal), _tk); 
        }
             
        exchange.transferBalance(msg.sender, value);
        // holding <= sellStock
        require(calcFreeBalance() > 0 && IOptionToken(_tk).balanceOf(address(this)) <= param.bsStockSpread[1], "bal 2 low/high volume");

        hedge(param);

        emit Sell(_tk, msg.sender, price, volume);
    }

    function getBalanceAndPayout() private view returns (uint bal, int pOut) {
        
        bal = exchange.balanceOf(address(this));
        pOut = exchange.calcExpectedPayout(address(this));
    }

    function hedge(PricingParameters memory param) private {
        //trigger hedge, may need to factor in costs and charge it to msg.sender
        if (_hedgingManagerAddress != address(0)) {
            IBaseHedgingManager(_hedgingManagerAddress).balanceExposure(
                param.udlFeed
            );
        }
    }

    function isInRange(
        string memory optSymbol,
        Operation op,
        address udlFeed
    )
        private
        view
        returns(bool)
    {
        Range memory r = ranges[optSymbol][uint(op)];
        if (r.start == 0 && r.end == 0) {
            return true;
        }
        int udlPrice = getUdlPrice(udlFeed);
        return uint(udlPrice) >= r.start && uint(udlPrice) <= r.end;
    }

    function validateOrder(
        uint volume,
        uint price, 
        string memory optSymbol, 
        Operation op,
        address _tk
    ) 
        private
        view
        returns (uint p, PricingParameters memory param) 
    {
        param = parameters[optSymbol];
        require(volume > 0 && isInRange(optSymbol, op, param.udlFeed), "bad rng or vol");
        p = calcOptPrice(
            param,
            op,
            IOptionToken(_tk).balanceOf(address(this)),
            IOptionToken(_tk).writtenVolume(address(this))
        );
        require(
            op == Operation.BUY ? price >= p : price <= p,
            "bad price"
        );
    }

    function valueOf(address ownr) override public view returns (uint) {
        (uint bal, int pOut) = getBalanceAndPayout();
        return uint(int(bal).add(pOut))
            .mul(balanceOf(ownr)).div(totalSupply());
    }
    
    function writeOptions(
        address _tk,
        PricingParameters memory param,
        uint volume,
        address to
    )
        virtual
        internal;

    function calcOptPrice(PricingParameters memory p, Operation op, uint poolPosBuy, uint poolPosSell)
        virtual
        internal
        view
        returns (uint price);

    function calcVolume(
        string memory optSymbol,
        PricingParameters memory p,
        uint price,
        Operation op,
        uint poolPos
    )
        virtual
        internal
        view
        returns (uint volume);

    function getUdlPrice(address udlFeed) internal view returns (int udlPrice) {
        (, udlPrice) = UnderlyingFeed(udlFeed).getLatestPrice();
    }

    function depositTokensInExchange(address token, uint value) private {
        IERC20_2(token).safeTransferFrom(msg.sender, address(this), value);
        IERC20_2(token).safeApprove(address(exchange), value);
        exchange.depositTokens(address(this), token, value);
    }

    function ensureCaller() private view {
        require(proposalManager.isRegisteredProposal(msg.sender) && IProposalWrapper(proposalManager.resolve(msg.sender)).isPoolSettingsAllowed(), "ONG");
    }

    function checkApproved(address udlFeed) private view {
        address ppk = UnderlyingFeed(udlFeed).getPrivledgedPublisherKeeper();
        if (ppk != address(0)) {
            require(ppk == tx.origin, "not approved");
        }
    }
}