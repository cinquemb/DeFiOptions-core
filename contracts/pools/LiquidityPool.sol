pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/ManagedContract.sol";
import "../interfaces/IOptionToken.sol";
import "../interfaces/IProposal.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/IYieldTracker.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IInterpolator.sol";
import "../finance/RedeemableToken.sol";
import "../utils/SafeCast.sol";
import "../utils/MoreMath.sol";
import "../utils/SignedSafeMath.sol";

abstract contract LiquidityPool is ManagedContract, RedeemableToken, ILiquidityPool {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    enum Operation { NONE, BUY, SELL }

    struct PricingParameters {
        address udlFeed;
        IOptionsExchange.OptionType optType;
        uint120 strike;
        uint32 maturity;
        uint32 t0;
        uint32 t1;
        uint120 buyStock;
        uint120 sellStock;
        uint120[] x;
        uint120[] y;
    }

    struct Range {
        uint120 start;
        uint120 end;
    }

    string internal _name;
    string internal _symbol;
    string internal constant _symbol_prefix = "LLPTK-";
    string internal constant _name_prefix = "Linear Liquidity Pool Redeemable Token: ";

    address private creditProviderAddr;

    IYieldTracker private tracker;
    IProtocolSettings private settings;
    IInterpolator internal interpolator;

    mapping(address => uint) private proposingId;
    mapping(uint => address) private proposalsMap;
    mapping(string => PricingParameters) private parameters;
    mapping(string => mapping(uint => Range)) private ranges;

    uint private serial;
    uint private _maturity;

    uint internal spread;
    uint internal volumeBase;
    uint internal reserveRatio;
    uint internal fractionBase;
    
    string[] private optSymbols;

    constructor(string memory _nm, string memory _sb, address _deployAddr)
        ERC20(string(abi.encodePacked(_name_prefix, _nm)))
        public
    {    
        _symbol = _sb;
        _name = _nm;

        Deployer deployer = Deployer(_deployAddr);
        fractionBase = 1e9;
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        creditProviderAddr = deployer.getContractAddress("CreditProvider");
        tracker = IYieldTracker(deployer.getContractAddress("YieldTracker"));
        interpolator = IInterpolator(deployer.getContractAddress("Interpolator"));
        volumeBase = exchange.volumeBase();
        serial = 1;
    }

    function setParameters(
        uint _spread,
        uint _reserveRatio,
        uint _mt
    )
        external
    {
        ensureCaller();
        spread = _spread;
        reserveRatio = _reserveRatio;
        _maturity = _mt;
    }

    function redeemAllowed() override public view returns (bool) {
        
        return block.timestamp >= _maturity;
    }

    function maturity() override external view returns (uint) {
        
        return _maturity;
    }

    function getOwner() override external view returns (address) {
        // returns the proposal address of the caller, used in removing pool symbols from exchange
        return proposalsMap[proposingId[msg.sender]];
    }

    function yield(uint dt) override external view returns (uint y) {
        y = tracker.yield(address(this), dt);
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
        uint buyStock,
        uint sellStock
    )
        external
    {
        ensureCaller();
        require(_mt < _maturity, "invalid maturity");
        require(x.length > 0 && x.length.mul(2) == y.length, "invalid pricing surface");

        IOptionsExchange.OptionData memory opt = IOptionsExchange.OptionData(udlFeed, optType, strike.toUint120(), _mt.toUint32());
        string memory optSymbol = exchange.getOptionSymbol(opt);

        if (parameters[optSymbol].x.length == 0) {
            optSymbols.push(optSymbol);
        } else {
            require(parameters[optSymbol].t1 < block.timestamp, "must be after t1");
        }

        parameters[optSymbol] = PricingParameters(
            udlFeed,
            optType,
            strike.toUint120(),
            _mt.toUint32(),
            t0.toUint32(),
            t1.toUint32(),
            buyStock.toUint120(),
            sellStock.toUint120(),
            x,
            y
        );

        emit AddSymbol(optSymbol);
    }

    function showSymbol(string calldata optSymbol) external view returns (uint32, uint120, uint120, uint120[] memory, uint120[] memory) {
        return (parameters[optSymbol].t1, parameters[optSymbol].buyStock, parameters[optSymbol].sellStock, parameters[optSymbol].x, parameters[optSymbol].y);
    }

    function setRange(string calldata optSymbol, Operation op, uint start, uint end) external {
        ensureCaller();
        ranges[optSymbol][uint(op)] = Range(start.toUint120(), end.toUint120());
    }

    function removeSymbol(string calldata optSymbol) external {
        ensureCaller();
        require(parameters[optSymbol].maturity >= block.timestamp, "cannot destroy befor maturity");
        
        PricingParameters memory empty;
        parameters[optSymbol] = empty;
        Arrays.removeItem(optSymbols, optSymbol);
        emit RemoveSymbol(optSymbol);
    }

    function depositTokens(address to, address token, uint value) override public {
        uint b0 = exchange.balanceOf(address(this));
        depositTokensInExchange(token, value);
        uint b1 = exchange.balanceOf(address(this));
        int po = exchange.calcExpectedPayout(address(this));
        
        tracker.push(
            block.timestamp.toUint32(), uint(int(b0).add(po)), b1.sub(b0)
        );

        uint ts = _totalSupply;
        int expBal = po.add(int(b1));
        uint p = b1.sub(b0).mul(fractionBase).div(uint(expBal));

        uint b = 1e3;
        uint v = ts > 0 ?
            ts.mul(p).mul(b).div(fractionBase.sub(p)) : 
            uint(expBal).mul(b);
        v = MoreMath.round(v, b);

        addBalance(to, v);
        _totalSupply = ts.add(v);
        emitTransfer(address(0), to, v);
    }

    function calcFreeBalance() public view returns (uint balance) {
        uint exBal = exchange.balanceOf(address(this));
        uint reserve = exBal.mul(reserveRatio).div(fractionBase);
        uint sp = exBal.sub(exchange.collateral(address(this)));
        balance = sp > reserve ? sp.sub(reserve) : 0;
    }
    
    function listSymbols() override external view returns (string memory available) {
        for (uint i = 0; i < optSymbols.length; i++) {
            if (parameters[optSymbols[i]].maturity > block.timestamp) {
                available = listSymbolHelper(available, optSymbols[i]);
            }
        }
    }

    function listExpiredSymbols() external view returns (string memory available) {
        for (uint i = 0; i < optSymbols.length; i++) {
            if (parameters[optSymbols[i]].maturity < block.timestamp) {
                available = listSymbolHelper(available, optSymbols[i]);
            }
        }
    }

    function listSymbolHelper(string memory buffer, string memory optSymbol) private pure returns (string memory) {
        if (bytes(buffer).length == 0) {
            buffer = optSymbol;
        } else {
            buffer = string(abi.encodePacked(buffer, "\n", optSymbol));
        }

        return buffer;
    }

    function queryBuy(string memory optSymbol)
        override
        public
        view
        returns (uint price, uint volume)
    {
        (price, volume) = queryHelper(optSymbol, Operation.BUY);
    }

    function querySell(string memory optSymbol)
        override
        public
        view
        returns (uint price, uint volume)
    {
        (price, volume) = queryHelper(optSymbol, Operation.SELL);
    }

    function queryHelper(string memory optSymbol, Operation op) private view returns (uint price, uint volume) {
        ensureValidSymbol(optSymbol);
        PricingParameters memory param = parameters[optSymbol];
        price = calcOptPrice(param, op);
        address _tk = exchange.resolveToken(optSymbol);
        uint optBal = (op == Operation.SELL) ? IOptionToken(_tk).balanceOf(address(this)) : IOptionToken(_tk).writtenVolume(address(this));
        volume = MoreMath.min(
            calcVolume(optSymbol, param, price, op),
            (op == Operation.SELL) ? uint(param.sellStock).sub(optBal) : uint(param.buyStock).sub(optBal)
        );
    }

    function buy(string memory optSymbol, uint price, uint volume, address token)
        override
        public
        returns (address _tk)
    {
        require(volume > 0, "invalid volume");
        ensureValidSymbol(optSymbol);

        PricingParameters memory param = parameters[optSymbol];

        require(isInRange(optSymbol, Operation.BUY, param.udlFeed), "out of range");

        price = receivePayment(param, price, volume, token);

        _tk = exchange.resolveToken(optSymbol);
        IOptionToken tk = IOptionToken(_tk);
        uint _holding = tk.balanceOf(address(this));

        if (volume > _holding) {
            writeOptions(tk, param, volume, msg.sender);
        } else {
            tk.transfer(msg.sender, volume);
        }

        emit Buy(_tk, msg.sender, price, volume);
    }

    function sell(string calldata optSymbol, uint price, uint volume) override external {
        
        require(volume > 0, "invalid volume");
        ensureValidSymbol(optSymbol);

        PricingParameters memory param = parameters[optSymbol];
        
        require(isInRange(optSymbol, Operation.SELL, param.udlFeed), "out of range");

        price = validatePrice(price, param, Operation.SELL);

        address _tk = exchange.resolveToken(optSymbol);
        IOptionToken tk = IOptionToken(_tk);
        tk.transferFrom(msg.sender, address(this), volume);
        
        uint _written = tk.writtenVolume(address(this));
        if (_written > 0) {
            uint toBurn = MoreMath.min(_written, volume);
            tk.burn(toBurn);
        }

        uint value = price.mul(volume).div(volumeBase);
        exchange.transferBalance(msg.sender, value);

        require(calcFreeBalance() > 0, "pool balance too low");

        uint _holding = tk.balanceOf(address(this));
        require(_holding <= param.sellStock, "excessive volume");

        emit Sell(_tk, msg.sender, price, volume);
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

    function receivePayment(
        PricingParameters memory param,
        uint price,
        uint volume,
        address token
    )
        private
        returns (uint)
    {
        price = validatePrice(price, param, Operation.BUY);
        uint value = price.mul(volume).div(volumeBase);

        if (token != address(exchange)) {
            (uint tv, uint tb) = settings.getTokenRate(token);
            value = value.mul(tv).div(tb);
            depositTokensInExchange(token, value);
        } else {
            exchange.transferBalance(msg.sender, address(this), value);
        }

        return price;
    }

    function validatePrice(
        uint price, 
        PricingParameters memory param, 
        Operation op
    ) 
        private
        view
        returns (uint p) 
    {
        p = calcOptPrice(param, op);
        require(
            op == Operation.BUY ? price >= p : price <= p,
            "insufficient price"
        );
    }

    function valueOf(address account) external view returns (uint) {

        int exBal = int(exchange.balanceOf(address(this)));
        int payout = exchange.calcExpectedPayout(address(this));
        return uint(exBal.add(payout))
            .mul(balanceOf(account)).div(totalSupply());
    }
    
    function writeOptions(
        IOptionToken tk,
        PricingParameters memory param,
        uint volume,
        address to
    )
        virtual
        internal;

    function calcOptPrice(PricingParameters memory p, Operation op)
        virtual
        internal
        view
        returns (uint price);

    function calcVolume(
        string memory optSymbol,
        PricingParameters memory p,
        uint price,
        Operation op
    )
        virtual
        internal
        view
        returns (uint volume);

    function getUdlPrice(address udlFeed) internal view returns (int udlPrice) {

        UnderlyingFeed feed = UnderlyingFeed(udlFeed);
        (, udlPrice) = feed.getLatestPrice();
    }

    function depositTokensInExchange(address token, uint value) private {
        
        IERC20 t = IERC20(token);
        t.transferFrom(msg.sender, creditProviderAddr, value);
        ICreditProvider(creditProviderAddr).addBalance(address(this), token, value);
    }

    function ensureValidSymbol(string memory optSymbol) private view {

        require(parameters[optSymbol].udlFeed != address(0), "invalid optSymbol");
    }

    function registerProposal(address addr) external returns (uint id) {
        require(
            proposingId[addr] == 0,
            "already proposed"
        );

        id = serial++;
        IProposal(addr).open(id);
        proposalsMap[id] = addr;
        proposingId[addr] = id;
    }

    function ensureCaller() private view {
        IProposal p = IProposal(msg.sender);
        require(proposalsMap[p.getId()] == msg.sender, "proposal not registered");
        require(p.isPoolSettingsAllowed(), "not allowed");
    }
}