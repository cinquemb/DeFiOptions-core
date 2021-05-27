pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../governance/ProtocolSettings.sol";
import "../utils/ERC20.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/LiquidityPool.sol";

import "../utils/Arrays.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeCast.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";
import "./CreditProvider.sol";
import "./OptionToken.sol";
import "./OptionTokenFactory.sol";
import "../pools/LinearLiquidityPoolFactory.sol";

contract OptionsExchange is ManagedContract {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;
    
    enum OptionType { CALL, PUT }
    
    struct OptionData {
        address udlFeed;
        OptionType _type;
        uint120 strike;
        uint32 maturity;
    }

    struct FeedData {
        uint120 lowerVol;
        uint120 upperVol;
    }
    
    ProtocolSettings private settings;
    CreditProvider private creditProvider;
    OptionTokenFactory private optionTokenFactory;
    LinearLiquidityPoolFactory private poolFactory;

    
    mapping(address => uint) public collateral;
    mapping(address => OptionData) private options;
    mapping(address => FeedData) private feeds;
    mapping(address => address[]) private book;

    mapping(string => address) private poolAddress;
    mapping(string => address) private tokenAddress;
    mapping(address => uint) public nonces;
    
    uint private _volumeBase;
    uint private timeBase;
    uint private sqrtTimeBase;

    string[] private poolSymbols;
    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    string private constant _name = "OptionsExchange";
    
    event RemovePoolSymbol(string symbolSuffix);
    event WithdrawTokens(address indexed from, uint value);
    event CreatePool(address indexed token, address indexed sender);
    event CreateSymbol(address indexed token, address indexed sender);

    event WriteOptions(
        address indexed token,
        address indexed issuer,
        address indexed onwer,
        uint volume
    );

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

    constructor() public {

        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(_name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    function initialize(Deployer deployer) override internal {

        DOMAIN_SEPARATOR = OptionsExchange(getImplementation()).DOMAIN_SEPARATOR();
        creditProvider = CreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        optionTokenFactory = OptionTokenFactory(deployer.getContractAddress("OptionTokenFactory"));
        poolFactory  = LinearLiquidityPoolFactory(deployer.getContractAddress("LinearLiquidityPoolFactory"));

        _volumeBase = 1e18;
        timeBase = 1e18;
        sqrtTimeBase = 1e9;
    }
    
    function name() external pure returns (string memory) {

        return _name;
    }

    function volumeBase() external view returns (uint) {
        return _volumeBase;
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
        external
    {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
        depositTokens(to, token, value);
    }

    function depositTokens(address to, address token, uint value) public {

        ERC20 t = ERC20(token);
        t.transferFrom(msg.sender, address(creditProvider), value);
        creditProvider.addBalance(to, token, value);
    }

    function balanceOf(address owner) external view returns (uint) {

        return creditProvider.balanceOf(owner);
    }

    function transferBalance(
        address from, 
        address to, 
        uint value
    )
        external
    {
        creditProvider.ensureCaller(msg.sender);
        creditProvider.transferBalance(from, to, value);
        ensureFunds(from);
    }

    function transferBalance(
        address from, 
        address to, 
        uint value,
        uint maxValue,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        require(maxValue >= value, "insufficient permit value");
        permit(from, to, maxValue, deadline, v, r, s);
        creditProvider.transferBalance(from, to, value);
        ensureFunds(from);
    }

    function transferBalance(address to, uint value) external {

        creditProvider.transferBalance(msg.sender, to, value);
        ensureFunds(msg.sender);
    }
    
    function withdrawTokens(uint value) external {
        
        require(value <= calcSurplus(msg.sender), "insufficient surplus");
        creditProvider.withdrawTokens(msg.sender, value);
        emit WithdrawTokens(msg.sender, value);
    }

    function createSymbol(string memory symbol, address udlFeed) public returns (address tk) {

        require(tokenAddress[symbol] == address(0), "already created");
        tk = optionTokenFactory.create(symbol, udlFeed);
        tokenAddress[symbol] = tk;
        prefetchFeedData(udlFeed);
        emit CreateSymbol(tk, msg.sender);
    }

    function createPool(string memory nameSuffix, string memory symbolSuffix) public returns (address pool) {

        require(poolAddress[symbolSuffix] == address(0), "already created");
        pool = poolFactory.create(nameSuffix, symbolSuffix, msg.sender);
        poolAddress[symbolSuffix] = pool;
        creditProvider.insertPoolCaller(pool);

        poolSymbols.push(symbolSuffix);
        emit CreatePool(pool, msg.sender);
    }

    function listPoolSymbols() external view returns (string memory available) {
        for (uint i = 0; i < poolSymbols.length; i++) {
            LiquidityPool llp = LiquidityPool(poolAddress[poolSymbols[i]]);
            if (llp.maturity() > settings.exchangeTime()) {
                available = listPoolSymbolHelper(available, poolSymbols[i]);
            }
        }
    }

    function listExpiredPoolSymbols() external view returns (string memory available) {
        for (uint i = 0; i < poolSymbols.length; i++) {
            LiquidityPool llp = LiquidityPool(poolAddress[poolSymbols[i]]);
            if (llp.maturity() < settings.exchangeTime()) {
                available = listPoolSymbolHelper(available, poolSymbols[i]);
            }
        }
    }

    function listPoolSymbolHelper(string memory buffer, string memory poolSymbol) internal pure returns (string memory) {
        if (bytes(buffer).length == 0) {
            buffer = poolSymbol;
        } else {
            buffer = string(abi.encodePacked(buffer, "\n", poolSymbol));
        }

        return buffer;
    }

    function removePoolSymbol(string calldata symbolSuffix) external {
        require(poolAddress[symbolSuffix] != address(0), "pool does not exist");

        LiquidityPool llp = LiquidityPool(poolAddress[symbolSuffix]);
        require(llp.getOwner() == msg.sender, "not owner");
        require(llp.maturity() >= settings.exchangeTime(), "cannot remove before maturity");
        
        poolAddress[symbolSuffix] = address(0);
        Arrays.removeItem(poolSymbols, symbolSuffix);
        emit RemovePoolSymbol(symbolSuffix);

    }
    
    function getOptionSymbol(
        address udlFeed,
        OptionType optType,
        uint strike, 
        uint maturity
    )
        public
        view
        returns (string memory symbol)
    {    
        symbol = string(abi.encodePacked(
            UnderlyingFeed(udlFeed).symbol(),
            "-",
            "E",
            optType == OptionType.CALL ? "C" : "P",
            "-",
            MoreMath.toString(strike),
            "-",
            MoreMath.toString(maturity)
        ));
    }

    function writeOptions(
        address udlFeed,
        uint volume,
        OptionType optType,
        uint strike, 
        uint maturity,
        address to
    )
        external 
        returns (address _tk)
    {
        (_tk) = writeOptionsInternal(udlFeed, volume, optType, strike, maturity, to);
        ensureFunds(msg.sender);
    }
    
    function transferOwnership(
        string calldata symbol,
        address from,
        address to,
        uint value
    )
        external
    {
        require(tokenAddress[symbol] == msg.sender, "unauthorized ownership transfer");        
        OptionToken tk = OptionToken(msg.sender);
        
        if (tk.writtenVolume(from) == 0 && tk.balanceOf(from) == 0) {
            Arrays.removeItem(book[from], msg.sender);
        }

        if (tk.writtenVolume(to) == 0 && tk.balanceOf(to) == value) {
            book[to].push(msg.sender);
        }

        ensureFunds(from);
    }

    function cleanUp(address _tk, address owner, uint volume) public {
        OptionToken tk = OptionToken(_tk);
        if (tk.balanceOf(owner) == 0 && tk.writtenVolume(owner) == 0) {
            Arrays.removeItem(book[owner], _tk);
        }
        uint coll = collateral[owner];
        collateral[owner] = coll.sub(
            MoreMath.min(coll, calcCollateral(options[_tk], volume))
        );
    }

    function liquidateExpired(address _tk, address[] calldata owners) external {

        OptionData memory opt = options[_tk];
        OptionToken tk = OptionToken(_tk);
        require(getUdlNow(opt) >= opt.maturity, "option not expired");
        uint iv = uint(calcIntrinsicValue(opt));

        for (uint i = 0; i < owners.length; i++) {
            liquidateOptions(owners[i], opt, tk, true, iv);
        }
    }

    function liquidateOptions(address _tk, address owner) public returns (uint value) {
        
        OptionData memory opt = options[_tk];
        require(opt.udlFeed != address(0), "invalid token");

        OptionToken tk = OptionToken(_tk);
        require(tk.writtenVolume(owner) > 0, "invalid owner");

        bool isExpired = getUdlNow(opt) >= opt.maturity;
        uint iv = uint(calcIntrinsicValue(opt));
        
        value = liquidateOptions(owner, opt, tk, isExpired, iv);
    }

    function calcSurplus(address owner) public view returns (uint) {
        
        uint coll = calcCollateral(owner, true);
        uint bal = creditProvider.balanceOf(owner);
        if (bal >= coll) {
            return bal.sub(coll);
        }
        return 0;
    }

    function calcCollateral(address owner, bool is_regular) public view returns (uint) {
        
        int coll;
        address[] memory _book = book[owner];

        for (uint i = 0; i < _book.length; i++) {

            address _tk = _book[i];
            OptionToken tk = OptionToken(_tk);
            OptionData memory opt = options[_tk];

            uint written = tk.writtenVolume(owner);
            uint holding = tk.balanceOf(owner);

            if (is_regular == false) {
                if (written > holding) {
                    continue;
                }
            }

            coll = coll.add(
                calcIntrinsicValue(opt).mul(
                    int(written).sub(int(holding))
                )
            ).add(int(calcCollateral(feeds[opt.udlFeed].upperVol, written, opt)));
        }

        coll = coll.div(int(_volumeBase));

        if (is_regular == false) {
            return uint(coll);
        }

        if (coll < 0)
            return 0;
        return uint(coll);
    }

    function calcCollateral(
        address udlFeed,
        uint volume,
        OptionType optType,
        uint strike, 
        uint maturity
    )
        public
        view
        returns (uint)
    {
        (OptionData memory opt,) = createOptionInMemory(udlFeed, optType, strike, maturity);
        return calcCollateral(opt, volume);
    }

    function calcExpectedPayout(address owner) external view returns (int payout) {

        address[] memory _book = book[owner];

        for (uint i = 0; i < _book.length; i++) {

            OptionToken tk = OptionToken(_book[i]);
            OptionData memory opt = options[_book[i]];

            uint written = tk.writtenVolume(owner);
            uint holding = tk.balanceOf(owner);

            payout = payout.add(
                calcIntrinsicValue(opt).mul(
                    int(holding).sub(int(written))
                )
            );
        }

        payout = payout.div(int(_volumeBase));
    }

    function calcIntrinsicValue(
        address udlFeed,
        OptionType optType,
        uint strike, 
        uint maturity
    )
        public
        view
        returns (int)
    {
        (OptionData memory opt,) = createOptionInMemory(udlFeed, optType, strike, maturity);
        return calcIntrinsicValue(opt);
    }

    function getUnderlyingPrice(string calldata symbol) external view returns (int) {
        
        address _ts = tokenAddress[symbol];
        require(_ts != address(0), "token not found");
        return getUdlPrice(options[_ts]);
    }

    function resolveToken(string calldata symbol) external view returns (address) {
        
        address addr = tokenAddress[symbol];
        require(addr != address(0), "token not found");
        return addr;
    }

    function prefetchFeedData(address udlFeed) public {
        
        feeds[udlFeed] = getFeedData(udlFeed);
    }

    function getBook(address owner)
        external view
        returns (
            string memory symbols,
            address[] memory tokens,
            uint[] memory holding,
            uint[] memory written,
            int[] memory iv
        )
    {
        tokens = book[owner];
        holding = new uint[](tokens.length);
        written = new uint[](tokens.length);
        iv = new int[](tokens.length);

        for (uint i = 0; i < tokens.length; i++) {
            OptionToken tk = OptionToken(tokens[i]);
            OptionData memory opt = options[tokens[i]];
            if (i == 0) {
                symbols = getOptionSymbol(opt);
            } else {
                symbols = string(abi.encodePacked(symbols, "\n", getOptionSymbol(opt)));
            }
            holding[i] = tk.balanceOf(owner);
            written[i] = tk.writtenVolume(owner);
            iv[i] = calcIntrinsicValue(opt);
        }
    }

    function ensureFunds(address owner) private view {
        require(
            creditProvider.balanceOf(owner) >= collateral[owner],
            "insufficient collateral"
        );
    }

    function permit(
        address from,
        address to,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        private
    {
        require(deadline >= settings.exchangeTime(), "permit expired");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(PERMIT_TYPEHASH, from, to, value, nonces[from]++, deadline)
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == from, "invalid signature");
    }

    function writeOptionsInternal(
        address udlFeed,
        uint volume,
        OptionType optType,
        uint strike, 
        uint maturity,
        address to
    )
        private 
        returns (address _tk)
    {
        require(settings.getUdlFeed(udlFeed) > 0, "feed not allowed");
        require(volume > 0, "invalid volume");
        require(maturity > settings.exchangeTime(), "invalid maturity");

        (OptionData memory opt, string memory symbol) =
            createOptionInMemory(udlFeed, optType, strike, maturity);

        _tk = tokenAddress[symbol];
        if (_tk == address(0)) {
            _tk = createSymbol(symbol, udlFeed);
        }

        OptionToken tk = OptionToken(_tk);
        if (tk.writtenVolume(msg.sender) == 0 && tk.balanceOf(msg.sender) == 0) {
            book[msg.sender].push(_tk);
        }
        if (msg.sender != to && tk.writtenVolume(to) == 0 && tk.balanceOf(to) == 0) {
            book[to].push(_tk);
        }
        tk.issue(msg.sender, to, volume);

        if (options[_tk].udlFeed == address(0)) {
            options[_tk] = opt;
        }
        
        collateral[msg.sender] = collateral[msg.sender].add(
            calcCollateral(opt, volume)
        );

        emit WriteOptions(_tk, msg.sender, to, volume);
    }

    function createOptionInMemory(
        address udlFeed,
        OptionType optType,
        uint strike, 
        uint maturity
    )
        private
        view
        returns (OptionData memory opt, string memory symbol)
    {
        opt = OptionData(udlFeed, optType, strike.toUint120(), maturity.toUint32());
        symbol = getOptionSymbol(opt);
    }

    function liquidateOptions(
        address owner,
        OptionData memory opt,
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
        OptionData memory opt,
        OptionToken tk,
        uint written,
        uint iv
    )
        private
        returns (uint value)
    {
        FeedData memory fd = feeds[opt.udlFeed];


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

    function calcLiquidationVolume(
        address owner,
        OptionData memory opt,
        FeedData memory fd,
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
        OptionData memory opt,
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

    function getFeedData(address udlFeed) private view returns (FeedData memory fd) {
        
        UnderlyingFeed feed = UnderlyingFeed(udlFeed);

        uint vol = feed.getDailyVolatility(settings.getVolatilityPeriod());

        fd = FeedData(
            feed.calcLowerVolatility(uint(vol)).toUint120(),
            feed.calcUpperVolatility(uint(vol)).toUint120()
        );
    }

    function getOptionSymbol(OptionData memory opt) public view returns (string memory symbol) {    

        symbol = getOptionSymbol(
            opt.udlFeed,
            opt._type,
            opt.strike,
            opt.maturity
        );
    }

    function calcCollateral(
        OptionData memory opt,
        uint volume
    )
        private
        view
        returns (uint)
    {
        FeedData memory fd = feeds[opt.udlFeed];
        if (fd.lowerVol == 0 || fd.upperVol == 0) {
            fd = getFeedData(opt.udlFeed);
        }

        int coll = calcIntrinsicValue(opt).mul(int(volume)).add(
            int(calcCollateral(fd.upperVol, volume, opt))
        ).div(int(_volumeBase));

        return coll > 0 ? uint(coll) : 0;
    }
    
    function calcCollateral(uint vol, uint volume, OptionData memory opt) private view returns (uint) {
        
        return (vol.mul(volume).mul(
            MoreMath.sqrt(daysToMaturity(opt)))
        ).div(sqrtTimeBase);
    }
    
    function calcIntrinsicValue(OptionData memory opt) private view returns (int value) {
        
        int udlPrice = getUdlPrice(opt);
        int strike = int(opt.strike);

        if (opt._type == OptionType.CALL) {
            value = MoreMath.max(0, udlPrice.sub(strike));
        } else if (opt._type == OptionType.PUT) {
            value = MoreMath.max(0, strike.sub(udlPrice));
        }
    }
    
    function daysToMaturity(OptionData memory opt) private view returns (uint d) {
        
        uint _now = getUdlNow(opt);
        if (opt.maturity > _now) {
            d = (timeBase.mul(uint(opt.maturity).sub(uint(_now)))).div(1 days);
        } else {
            d = 0;
        }
    }

    function getUdlPrice(OptionData memory opt) private view returns (int answer) {

        if (opt.maturity > settings.exchangeTime()) {
            (,answer) = UnderlyingFeed(opt.udlFeed).getLatestPrice();
        } else {
            (,answer) = UnderlyingFeed(opt.udlFeed).getPrice(opt.maturity);
        }
    }

    function getUdlNow(OptionData memory opt) private view returns (uint timestamp) {

        (timestamp,) = UnderlyingFeed(opt.udlFeed).getLatestPrice();
    }
}
