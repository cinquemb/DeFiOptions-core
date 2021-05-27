pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/ManagedContract.sol";
import "../finance/OptionToken.sol";
import "../finance/RedeemableToken.sol";
import "../interfaces/IProposal.sol";
import "../interfaces/LiquidityPool.sol";
import "../interfaces/IInterpolator.sol";
import "../interfaces/IYieldTracker.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IProtocolSettings.sol";
import "../utils/SafeCast.sol";
import "../utils/MoreMath.sol";
import "../utils/SignedSafeMath.sol";

contract LinearLiquidityPool is LiquidityPool, ManagedContract, RedeemableToken {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    enum Operation { NONE, BUY, SELL }

    struct PricingParameters {
        address udlFeed;
        IOptionsExchange.OptionType optType;
        uint120 strike;
        uint32 maturity;
        uint256 lastUpdateTime;
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
        
    string private _name;
    string private _symbol;
    string private constant _symbol_prefix = "LLPTK-";
    string private constant _name_prefix = "Linear Liquidity Pool Redeemable Token: ";

    address private owner;
    address private trackerAddr;
    address private settingsAddr;
    address private interpolatorAddr;
    address private creditProviderAddr;
    
    uint private serial;
    uint private spread;
    uint private _maturity;
    uint private volumeBase;
    uint private reserveRatio;
    uint private fractionBase;
    string[] private optSymbols;

    mapping(address => uint) private proposingId;
    mapping(uint => address) private proposalsMap;
    mapping(string => PricingParameters) private parameters;
    mapping(string => mapping(uint => Range)) private ranges;

    constructor(string memory _nm, string memory _sb, address _ownerAddr, address _deployAddr)
        ERC20(string(abi.encodePacked(_name_prefix, _name)))
        public
    {    
        _symbol = _sb;
        _name = _nm;
        owner = _ownerAddr;

        Deployer deployer = Deployer(_deployAddr);
        fractionBase = 1e9;
        exchangeAddr = deployer.getContractAddress("OptionsExchange");
        settingsAddr = deployer.getContractAddress("ProtocolSettings");
        creditProviderAddr = deployer.getContractAddress("CreditProvider");
        interpolatorAddr = deployer.getContractAddress("Interpolator");
        trackerAddr = deployer.getContractAddress("YieldTracker");
        volumeBase = IOptionsExchange(exchangeAddr).volumeBase();
        DOMAIN_SEPARATOR = ERC20(getImplementation()).DOMAIN_SEPARATOR();
        serial = 1;
    }

    function name() override external view returns (string memory) {
        return string(abi.encodePacked(_name_prefix, _name));
    }

    function symbol() override external view returns (string memory) {

        return string(abi.encodePacked(_symbol_prefix, _symbol));
    }

    function totalSupply() override external view returns (uint) {
        return _totalSupply;
    }

    function setParameters(
        uint _spread,
        uint _reserveRatio,
        uint _mt
    )
        external
    {
        ensureOwner();
        spread = _spread;
        reserveRatio = _reserveRatio;
        _maturity = _mt;
    }

    function redeemAllowed() override public view returns (bool) {
        
        return IProtocolSettings(settingsAddr).exchangeTime() >= _maturity;
    }

    function maturity() override external view returns (uint) {
        
        return _maturity;
    }

    function getOwner() override external view returns (address) {
        return owner;
    }

    function yield(uint dt) override external view returns (uint y) {
        y = IYieldTracker(trackerAddr).yield(address(this), dt);
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
        string memory optSymbol = IOptionsExchange(exchangeAddr).getOptionSymbol(opt);

        uint256 exchangeTime = IProtocolSettings(settingsAddr).exchangeTime();

        if (parameters[optSymbol].x.length == 0) {
            ensureOwner();
            optSymbols.push(optSymbol);
        } else {
            if (msg.sender != owner) {
                require(parameters[optSymbol].t1 < exchangeTime, "must be after t1");
            }
        }

        parameters[optSymbol] = PricingParameters(
            udlFeed,
            optType,
            strike.toUint120(),
            _mt.toUint32(),
            uint(exchangeTime),
            t0.toUint32(),
            t1.toUint32(),
            buyStock.toUint120(),
            sellStock.toUint120(),
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
        ensureCaller();
        require(parameters[optSymbol].maturity >= IProtocolSettings(settingsAddr).exchangeTime(), "cannot destroy befor maturity");
        
        PricingParameters memory empty;
        parameters[optSymbol] = empty;
        Arrays.removeItem(optSymbols, optSymbol);
        emit RemoveSymbol(optSymbol);
    }

    function depositTokens(
        address to,
        address token,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        override
        external
    {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
        depositTokens(to, token, value);
    }

    function depositTokens(address to, address token, uint value) override public {

        uint b0 = IOptionsExchange(exchangeAddr).balanceOf(address(this));
        depositTokensInExchange(token, value);
        uint b1 = IOptionsExchange(exchangeAddr).balanceOf(address(this));
        int po = IOptionsExchange(exchangeAddr).calcExpectedPayout(address(this));
        
        IYieldTracker(trackerAddr).push(
            IProtocolSettings(settingsAddr).exchangeTime().toUint32(), uint(int(b0).add(po)), b1.sub(b0)
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

        uint exBal = IOptionsExchange(exchangeAddr).balanceOf(address(this));
        uint reserve = exBal.mul(reserveRatio).div(fractionBase);
        uint sp = exBal.sub(IOptionsExchange(exchangeAddr).collateral(address(this)));
        balance = sp > reserve ? sp.sub(reserve) : 0;
    }
    
    function listSymbols() override external view returns (string memory available) {
        for (uint i = 0; i < optSymbols.length; i++) {
            if (parameters[optSymbols[i]].maturity > IProtocolSettings(settingsAddr).exchangeTime()) {
                available = listSymbolHelper(available, optSymbols[i]);
            }
        }
    }

    function listExpiredSymbols() external view returns (string memory available) {
        for (uint i = 0; i < optSymbols.length; i++) {
            if (parameters[optSymbols[i]].maturity < IProtocolSettings(settingsAddr).exchangeTime()) {
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

    function poolBalanceOf(address from) override external view returns (uint balance) {
        balance = balanceOf(from);
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
        address _tk = IOptionsExchange(exchangeAddr).resolveToken(optSymbol);
        uint optBal = (op == Operation.SELL) ? OptionToken(_tk).balanceOf(address(this)) : OptionToken(_tk).writtenVolume(address(this));
        volume = MoreMath.min(
            calcVolume(optSymbol, param, price, op),
            (op == Operation.SELL) ? uint(param.sellStock).sub(optBal) : uint(param.buyStock).sub(optBal)
        );
    }
    
    function buy(
        string calldata optSymbol,
        uint price,
        uint volume,
        address token,
        uint maxValue,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        override
        external
        returns (address _tk)
    {        
        IERC20Permit(token).permit(msg.sender, address(this), maxValue, deadline, v, r, s);
        _tk = buy(optSymbol, price, volume, token);
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

        _tk = IOptionsExchange(exchangeAddr).resolveToken(optSymbol);
        OptionToken tk = OptionToken(_tk);
        uint _holding = tk.balanceOf(address(this));

        if (volume > _holding) {
            writeOptions(tk, param, volume, msg.sender);
        } else {
            tk.transfer(msg.sender, volume);
        }

        emit Buy(_tk, msg.sender, price, volume);
    }

    function sell(
        string memory optSymbol,
        uint price,
        uint volume,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        override
        public
    {
        require(volume > 0, "invalid volume");
        ensureValidSymbol(optSymbol);

        PricingParameters memory param = parameters[optSymbol];
        
        require(isInRange(optSymbol, Operation.SELL, param.udlFeed), "out of range");

        price = validatePrice(price, param, Operation.SELL);

        address _tk = IOptionsExchange(exchangeAddr).resolveToken(optSymbol);
        OptionToken tk = OptionToken(_tk);
        if (deadline > 0) {
            tk.permit(msg.sender, address(this), volume, deadline, v, r, s);
        }
        tk.transferFrom(msg.sender, address(this), volume);
        
        uint _written = tk.writtenVolume(address(this));
        if (_written > 0) {
            uint toBurn = MoreMath.min(_written, volume);
            tk.burn(toBurn);
        }

        uint value = price.mul(volume).div(volumeBase);
        IOptionsExchange(exchangeAddr).transferBalance(msg.sender, value);

        require(calcFreeBalance() > 0, "pool balance too low");

        uint _holding = tk.balanceOf(address(this));
        require(_holding <= param.sellStock, "excessive volume");

        emit Sell(_tk, msg.sender, price, volume);
    }

    function sell(string calldata optSymbol, uint price, uint volume) override external {
        
        bytes32 x;
        sell(optSymbol, price, volume, 0, 0, x, x);
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

        if (token != exchangeAddr) {
            (uint tv, uint tb) = IProtocolSettings(settingsAddr).getTokenRate(token);
            value = value.mul(tv).div(tb);
            depositTokensInExchange(token, value);
        } else {
            IOptionsExchange(exchangeAddr).transferBalance(msg.sender, address(this), value);
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

    function writeOptions(
        OptionToken tk,
        PricingParameters memory param,
        uint volume,
        address to
    )
        private
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
        private
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
        private
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

    function getUdlPrice(address udlFeed) private view returns (int udlPrice) {
        UnderlyingFeed feed = UnderlyingFeed(udlFeed);
        (, udlPrice) = feed.getLatestPrice();
    }

    function depositTokensInExchange(address token, uint value) private {
        
        ERC20 t = ERC20(token);
        t.transferFrom(msg.sender, creditProviderAddr, value);
        ICreditProvider(creditProviderAddr).addBalance(address(this), token, value);
    }

    function ensureValidSymbol(string memory optSymbol) private view {

        require(parameters[optSymbol].udlFeed !=  address(0), "invalid optSymbol");
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
        if (owner != address(0)) {
            if (msg.sender != owner) {
                IProposal p = IProposal(msg.sender);
                require(proposalsMap[p.getId()] == msg.sender, "proposal not registered");
                require(p.isPoolSettingsAllowed(), "not allowed");
            }
        } else {
            require(owner == address(0) || msg.sender == owner, "unauthorized caller");
        }
    }

    function ensureOwner() private view {
        require(owner == address(0) || msg.sender == owner, "unauthorized caller");
    }
}