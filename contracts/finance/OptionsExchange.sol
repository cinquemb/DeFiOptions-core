pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../governance/ProtocolSettings.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/LiquidityPool.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/ICollateralManager.sol";

import "../utils/ERC20.sol";
import "../utils/Arrays.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeCast.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";
import "./OptionToken.sol";
import "./OptionTokenFactory.sol";
import "../pools/LinearLiquidityPoolFactory.sol";

contract OptionsExchange is ManagedContract {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;
    
    ProtocolSettings private settings;
    ICreditProvider private creditProvider;
    OptionTokenFactory private optionTokenFactory;
    LinearLiquidityPoolFactory private poolFactory;
    ICollateralManager private collateralManager;
    
    mapping(address => uint) public collateral;
    mapping(address => IOptionsExchange.OptionData) private options;
    mapping(address => IOptionsExchange.FeedData) private feeds;
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
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        optionTokenFactory = OptionTokenFactory(deployer.getContractAddress("OptionTokenFactory"));
        poolFactory  = LinearLiquidityPoolFactory(deployer.getContractAddress("LinearLiquidityPoolFactory"));
        collateralManager = ICollateralManager(deployer.getContractAddress("CollateralManager"));

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
        int excessCollateral = collateralManager.collateralSkew();
        t.transferFrom(msg.sender, address(creditProvider), value);

        /* 
            if shortage:
                deduct from creditited value;
            if excesss
                add to credited value;
        */        
        
        uint creditingValue = uint(int(value).sub(excessCollateral));
        creditProvider.addBalance(to, token, creditingValue);
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
        IOptionsExchange.OptionType optType,
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
            optType == IOptionsExchange.OptionType.CALL ? "C" : "P",
            "-",
            MoreMath.toString(strike),
            "-",
            MoreMath.toString(maturity)
        ));
    }

    function writeOptions(
        address udlFeed,
        uint volume,
        IOptionsExchange.OptionType optType,
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
            MoreMath.min(coll, collateralManager.calcCollateral(options[_tk], volume))
        );
    }

    function liquidateExpired(address _tk, address[] calldata owners) external {
        collateralManager.liquidateExpired(_tk, owners);
    }

    function liquidateOptions(address _tk, address owner) public returns (uint value) {
        value = collateralManager.liquidateOptions(_tk, owner);
    }

    function calcSurplus(address owner) public view returns (uint) {
        
        uint coll = collateralManager.calcCollateral(owner, true);
        uint bal = creditProvider.balanceOf(owner);
        if (bal >= coll) {
            return bal.sub(coll);
        }
        return 0;
    }

    function calcCollateral(address owner, bool is_regular) public view returns (uint) {
        return collateralManager.calcCollateral(owner, is_regular);
    }

    function calcCollateral(
        address udlFeed,
        uint volume,
        IOptionsExchange.OptionType optType,
        uint strike, 
        uint maturity
    )
        public
        view
        returns (uint)
    {
        (IOptionsExchange.OptionData memory opt,) = createOptionInMemory(udlFeed, optType, strike, maturity);
        return collateralManager.calcCollateral(opt, volume);
    }

    function calcExpectedPayout(address owner) external view returns (int payout) {
        payout = collateralManager.calcExpectedPayout(owner);
    }

    function calcIntrinsicValue(
        address udlFeed,
        IOptionsExchange.OptionType optType,
        uint strike, 
        uint maturity
    )
        public
        view
        returns (int)
    {
        (IOptionsExchange.OptionData memory opt,) = createOptionInMemory(udlFeed, optType, strike, maturity);
        return collateralManager.calcIntrinsicValue(opt);
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

    function getExchangeFeeds(address udlFeed) external view returns (IOptionsExchange.FeedData memory) {
        return feeds[udlFeed];
    }

    function getOptionData(address tkAddr) external view returns (IOptionsExchange.OptionData memory) {
        return options[tkAddr];
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
            IOptionsExchange.OptionData memory opt = options[tokens[i]];
            if (i == 0) {
                symbols = getOptionSymbol(opt);
            } else {
                symbols = string(abi.encodePacked(symbols, "\n", getOptionSymbol(opt)));
            }
            holding[i] = tk.balanceOf(owner);
            written[i] = tk.writtenVolume(owner);
            iv[i] = collateralManager.calcIntrinsicValue(opt);
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
        IOptionsExchange.OptionType optType,
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

        (IOptionsExchange.OptionData memory opt, string memory symbol) =
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
            collateralManager.calcCollateral(opt, volume)
        );

        emit WriteOptions(_tk, msg.sender, to, volume);
    }

    function createOptionInMemory(
        address udlFeed,
        IOptionsExchange.OptionType optType,
        uint strike, 
        uint maturity
    )
        private
        view
        returns (IOptionsExchange.OptionData memory opt, string memory symbol)
    {
        opt = IOptionsExchange.OptionData(udlFeed, optType, strike.toUint120(), maturity.toUint32());
        symbol = getOptionSymbol(opt);
    }

    function getFeedData(address udlFeed) public view returns (IOptionsExchange.FeedData memory fd) {
        
        UnderlyingFeed feed = UnderlyingFeed(udlFeed);

        uint vol = feed.getDailyVolatility(settings.getVolatilityPeriod());

        fd = IOptionsExchange.FeedData(
            feed.calcLowerVolatility(uint(vol)).toUint120(),
            feed.calcUpperVolatility(uint(vol)).toUint120()
        );
    }

    function getOptionSymbol(IOptionsExchange.OptionData memory opt) public view returns (string memory symbol) {    

        symbol = getOptionSymbol(
            opt.udlFeed,
            opt._type,
            opt.strike,
            opt.maturity
        );
    }

    function getUdlPrice(IOptionsExchange.OptionData memory opt) internal view returns (int answer) {

        if (opt.maturity > settings.exchangeTime()) {
            (,answer) = UnderlyingFeed(opt.udlFeed).getLatestPrice();
        } else {
            (,answer) = UnderlyingFeed(opt.udlFeed).getPrice(opt.maturity);
        }
    }

    function prefetchSample(address udlFeed) incentivized external {
        UnderlyingFeed(udlFeed).prefetchSample();
    }

    function pprefetchDailyPrice(address udlFeed, uint roundId) incentivized external {
        UnderlyingFeed(udlFeed).prefetchDailyPrice(roundId);
    }

    function prefetchDailyVolatility(address udlFeed, uint timespan) incentivized external {
        UnderlyingFeed(udlFeed).prefetchDailyVolatility(timespan);
    }

    modifier incentivized() {
        uint256 startGas = gasleft();

        _;
        
        uint256 gasUsed = startGas - gasleft();
        address[] memory tokens = settings.getAllowedTokens();

        /* TODO:
            use gas price oracle to multiply current gas price by gas used, convert to $, debit exchange balance
        */

        uint256 creditingValue = 0e18;
        
        if (tokens.length > 0) {
            creditProvider.addBalance(msg.sender, tokens[0], creditingValue);
        }
        
    }
}
