pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../finance/RedeemableToken.sol";
import "../governance/ProtocolSettings.sol";
import "../interfaces/LiquidityPool.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../utils/SafeCast.sol";
import "../utils/SignedSafeMath.sol";
import "../finance/OptionToken.sol";

contract LinearLiquidityPool is LiquidityPool, ManagedContract, RedeemableToken {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    enum Operation { BUY, SELL }

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

    struct Deposit {
        uint32 date;
        uint balance;
        uint value;
    }

    ProtocolSettings private settings;
    CreditProvider private creditProvider;

    mapping(string => PricingParameters) private parameters;

    string private constant _name_prefix = "Linear Liquidity Pool Redeemable Token: ";
    string private constant _symbol_prefix = "LLPTK-";
    string private _symbol;
    string private _name;

    address private owner;
    uint private serial;
    uint private spread;
    uint private _maturity;
    uint private volumeBase;
    uint private reserveRatio;
    uint private fractionBase;
    string[] private optSymbols;
    Deposit[] private deposits;

    mapping(address => uint) private proposingId;
    mapping(uint => address) private proposalsMap;
    mapping(string => PricingParameters) private parameters;

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
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        creditProvider = CreditProvider(deployer.getContractAddress("CreditProvider"));
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
        
        return settings.exchangeTime() >= _maturity;
    }

    function maturity() override external view returns (uint) {
        
        return _maturity;
    }

    function getOwner() override external view returns (address) {
        return owner;
    }

    function yield(uint dt) override external view returns (uint y) {
        
        y = fractionBase;

        if (deposits.length > 0) {
            
            uint _now = settings.exchangeTime();
            uint start = _now.sub(dt);
            
            uint i = 0;
            for (i = 0; i < deposits.length; i++) {
                if (deposits[i].date > start) {
                    break;
                }
            }

            for (; i <= deposits.length; i++) {
                if (i > 0) {
                    y = y.mul(calcYield(i, start)).div(fractionBase);
                }
            }
        }
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

        uint256 exchangeTime = settings.exchangeTime();

        if (parameters[optSymbol].x.length == 0) {
            ensureOwner();
            optSymbols.push(optSymbol);
        } else {
            require(uint(exchangeTime) >= parameters[optSymbol].t1, "cannot update yet");
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

    function removeSymbol(string calldata optSymbol) external {
        ensureCaller();
        require(parameters[optSymbol].maturity >= settings.exchangeTime(), "cannot destroy befor maturity");
        
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
        ERC20(token).permit(msg.sender, address(this), value, deadline, v, r, s);
        depositTokens(to, token, value);
    }

    function depositTokens(address to, address token, uint value) override public {

        uint b0 = IOptionsExchange(exchangeAddr).balanceOf(address(this));
        depositTokensInExchange(token, value);
        uint b1 = IOptionsExchange(exchangeAddr).balanceOf(address(this));
        int po = IOptionsExchange(exchangeAddr).calcExpectedPayout(address(this));
        
        deposits.push(
            Deposit(settings.exchangeTime().toUint32(), uint(int(b0).add(po)), b1.sub(b0))
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
            if (parameters[optSymbols[i]].maturity > settings.exchangeTime()) {
                available = listSymbolHelper(available, optSymbols[i]);
            }
        }
    }

    function listExpiredSymbols() external view returns (string memory available) {
        for (uint i = 0; i < optSymbols.length; i++) {
            if (parameters[optSymbols[i]].maturity < settings.exchangeTime()) {
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
        string memory optSymbol,
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
        public
        returns (address _tk)
    {
        require(volume > 0, "invalid volume");
        ensureValidSymbol(optSymbol);

        PricingParameters memory param = parameters[optSymbol];
        price = receivePayment(param, price, volume, maxValue, token, deadline, v, r, s);

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

    function buy(string calldata optSymbol, uint price, uint volume, address token)
        override
        external
        returns (address _tk)
    {
        bytes32 x;
        uint maxValue = price.mul(volume).div(volumeBase);
        _tk = buy(optSymbol, price, volume, token, maxValue, 0, 0, x, x);
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

    function receivePayment(
        PricingParameters memory param,
        uint price,
        uint volume,
        uint maxValue,
        address token,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        private
        returns (uint)
    {
        price = validatePrice(price, param, Operation.BUY);
        uint value = price.mul(volume).div(volumeBase);

        if (token != exchangeAddr) {
            (uint tv, uint tb) = settings.getTokenRate(token);
            if (deadline > 0) {
                ERC20(token).permit(msg.sender, address(this), maxValue, deadline, v, r, s);
            }
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
        
        (uint j, uint xp) = findUdlPrice(p);
        uint _now = settings.exchangeTime();
        uint dt = uint(p.t1).sub(uint(p.t0));
        require(_now >= p.t0 && _now <= p.t1, "calcOptPrice: _now < p.t0 | _now > p.t1");
        
        uint t = _now.sub(p.t0);
        uint p0 = calcOptPriceAt(p, 0, j, xp);
        uint p1 = calcOptPriceAt(p, p.x.length, j, xp);

        uint dp0p1 = uint(MoreMath.abs(int(p0).sub(int(p1))));

        if (p0 >= p1) {
            price = p0.mul(dt).sub(
                t.mul(dp0p1)
            ).mul(f).div(fractionBase).div(dt);
        } else {
            price = p0.mul(dt).add(
                t.mul(dp0p1)
            ).mul(f).div(fractionBase).div(dt);
        }
    }

    function findUdlPrice(PricingParameters memory p) private view returns (uint j, uint xp) {

        UnderlyingFeed feed = UnderlyingFeed(p.udlFeed);
        (,int udlPrice) = feed.getLatestPrice();
        xp = uint(udlPrice);

        while (p.x[j] < xp && j < p.x.length) {
            j++;
        }

        require(j > 0 && j < p.x.length, "findUdlPrice: invalid pricing parameters");
    }

    function calcOptPriceAt(
        PricingParameters memory p,
        uint offset,
        uint j,
        uint xp
    )
        private
        pure
        returns (uint price)
    {
        uint k = offset.add(j);
        require(k < p.y.length, "error calcOptPriceAt: k >= p.y.length");
        int yA = int(p.y[k]);
        int yB = int(p.y[k - 1]);
        int xN = int(xp.sub(p.x[j - 1]));
        int xD = int(p.x[j]).sub(int(p.x[j - 1]));

        require(xD != 0, "error calcOptPriceAt: xD == 0");

        (int y1, int y2) = (0, 0);
        
        if (yA >= yB) {
            y1 = yA.sub(yB);
            y2 = yB;
        } else {
            y1 = yB.sub(yA);
            y2 = yA;
        }

        price = uint(
            y1.mul(
                xN
            ).div(
                xD
            ).add(y2)
        );
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

    function calcYield(uint index, uint start) private view returns (uint y) {

        uint t0 = deposits[index - 1].date;
        uint t1 = index < deposits.length ?
            deposits[index].date : settings.exchangeTime();

        int v0 = int(deposits[index - 1].value.add(deposits[index - 1].balance));
        int v1 = index < deposits.length ? 
            int(deposits[index].balance) :
            IOptionsExchange(exchangeAddr).calcExpectedPayout(address(this)).add(int(IOptionsExchange(exchangeAddr).balanceOf(address(this))));

        y = uint(v1.mul(int(fractionBase)).div(v0));
        if (start > t0) {
            y = MoreMath.powDecimal(
                y, 
                (t1.sub(start)).mul(fractionBase).div(t1.sub(t0)), 
                fractionBase
            );
        }
    }

    function depositTokensInExchange(address token, uint value) private {
        
        ERC20 t = ERC20(token);
        t.transferFrom(msg.sender, address(creditProvider), value);
        creditProvider.addBalance(address(this), token, value);
    }

    function ensureValidSymbol(string memory optSymbol) private view {

        require(parameters[optSymbol].udlFeed !=  address(0), "invalid optSymbol");
    }

    function registerProposal(address addr) external returns (uint id) {
        require(
            proposingId[addr] == 0,
            "already proposed"
        );

        Proposal p = Proposal(addr);
        id = serial++;
        p.open(id);
        proposalsMap[id] = addr;
        proposingId[addr] = id;
    }

    function ensureCaller() private view {
        if (owner != address(0)) {
            if (msg.sender != owner) {
                Proposal p = Proposal(msg.sender);
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