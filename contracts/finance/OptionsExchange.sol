pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/IBaseCollateralManager.sol";
import "../interfaces/IUnderlyingVault.sol";

import "../utils/Arrays.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeCast.sol";
import "../utils/SafeERC20.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";
import "./OptionToken.sol";
import "./OptionTokenFactory.sol";
import "../feeds/DEXFeedFactory.sol";
import "../feeds/DEXAggregatorV1.sol";
import "../pools/LinearLiquidityPoolFactory.sol";

contract OptionsExchange is ManagedContract {

    using SafeCast for uint;
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using SignedSafeMath for int;
    
    IUnderlyingVault private vault;
    IProtocolSettings private settings;
    ICreditProvider private creditProvider;
    DEXFeedFactory private dexFeedFactory;
    IBaseCollateralManager private collateralManager;

    OptionTokenFactory private optionTokenFactory;
    LinearLiquidityPoolFactory private poolFactory;

    mapping(address => uint) public collateral;

    mapping(address => IOptionsExchange.OptionData) private options;
    mapping(address => IOptionsExchange.FeedData) private feeds;
    mapping(address => address[]) private book;

    mapping(string => address) private poolAddress;
    mapping(string => address) private tokenAddress;
    mapping(address => address) private dexFeedAddress;

    mapping(address => mapping(address => uint)) private allowed;    

    uint private _volumeBase;

    string[] private poolSymbols;
    address[] private dexFeedAddresses;
    
    event WithdrawTokens(address indexed from, uint value);
    event IncentiveReward(address indexed from, uint value);
    event CreatePool(address indexed token, address indexed sender);
    event CreateSymbol(address indexed token, address indexed sender);
    event CreateDexFeed(address indexed feed, address indexed sender);

    event Approval(address indexed owner, address indexed spender, uint value);

    event WriteOptions(
        address indexed token,
        address indexed issuer,
        address indexed onwer,
        uint volume
    );

    function initialize(Deployer deployer) override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        optionTokenFactory = OptionTokenFactory(deployer.getContractAddress("OptionTokenFactory"));
        poolFactory  = LinearLiquidityPoolFactory(deployer.getContractAddress("LinearLiquidityPoolFactory"));
        collateralManager = IBaseCollateralManager(deployer.getContractAddress("CollateralManager"));
        vault = IUnderlyingVault(deployer.getContractAddress("UnderlyingVault"));

        _volumeBase = 1e18;
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

        IERC20 t = IERC20(token);
        t.safeTransferFrom(msg.sender, address(creditProvider), value);
        creditProvider.addBalance(to, token, value);
    }

    function balanceOf(address owner) external view returns (uint) {

        return creditProvider.balanceOf(owner);
    }

    function allowance(address owner, address spender) external view returns (uint) {

        return allowed[owner][spender];
    }

    function approve(address spender, uint value) external returns (bool) {

        require(spender != address(0));
        allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferBalance(
        address from, 
        address to, 
        uint value
    )
        external
    {

        uint allw = allowed[from][msg.sender];
        if (allw >= value) {
            allowed[from][msg.sender] = allw.sub(value);
        } else {
            creditProvider.ensureCaller(msg.sender);
        }
        creditProvider.transferBalance(from, to, value);
        ensureFunds(from);
    }

    function transferBalance(address to, uint value) external {
        creditProvider.transferBalance(msg.sender, to, value);
        ensureFunds(msg.sender);
    }

    function underlyingBalance(address owner, address _tk) external view returns (uint) {

        return vault.balanceOf(owner, _tk);
    }
    
    function withdrawTokens(uint value) external {
        
        require(value <= calcSurplus(msg.sender), "insufficient surplus");
        creditProvider.withdrawTokens(msg.sender, value);
        emit WithdrawTokens(msg.sender, value);
    }

    function createSymbol(
        address udlFeed,
        IOptionsExchange.OptionType optType,
        uint strike, 
        uint maturity
    )
        public
        returns (address tk)
    {
        ensureFeedIsAlowed(udlFeed);
        (IOptionsExchange.OptionData memory opt, string memory symbol) = createOptionInMemory(udlFeed, optType, strike, maturity);

        require(tokenAddress[symbol] == address(0), "already created");
        tk = optionTokenFactory.create(symbol, udlFeed);
        tokenAddress[symbol] = tk;
        options[tk] = opt;
        prefetchFeedData(udlFeed);

        emit CreateSymbol(tk, msg.sender);
    }

    function createPool(string memory nameSuffix, string memory symbolSuffix) public returns (address pool) {

        require(poolAddress[symbolSuffix] == address(0), "already created");
        pool = poolFactory.create(nameSuffix, symbolSuffix);
        poolAddress[symbolSuffix] = pool;
        creditProvider.insertPoolCaller(pool);

        poolSymbols.push(symbolSuffix);
        emit CreatePool(pool, msg.sender);
        return pool;
    }

    function listPoolSymbols(uint offset, uint range) external view returns (string memory available) {
        for (uint i = offset; i < range; i++) {
            ILiquidityPool llp = ILiquidityPool(poolAddress[poolSymbols[i]]);
            if (llp.maturity() > settings.exchangeTime()) {
                available = listPoolSymbolHelper(available, poolSymbols[i]);
            }
        }
    }

    function totalPoolSymbols() external view returns (uint) {
        return poolSymbols.length;
    }

    function listExpiredPoolSymbols() external view returns (string memory available) {
        for (uint i = 0; i < poolSymbols.length; i++) {
            ILiquidityPool llp = ILiquidityPool(poolAddress[poolSymbols[i]]);
            if (llp.maturity() < settings.exchangeTime()) {
                available = listPoolSymbolHelper(available, poolSymbols[i]);
            }
        }
    }

    function listPoolSymbolHelper(string memory buffer, string memory poolSymbol) private pure returns (string memory) {
        if (bytes(buffer).length == 0) {
            buffer = poolSymbol;
        } else {
            buffer = string(abi.encodePacked(buffer, "\n", poolSymbol));
        }

        return buffer;
    }

    function getPoolAddress(string calldata poolSymbol) external view returns (address)  {
        return poolAddress[poolSymbol];
    }

    function createDexFeed(address underlying, address stable, address dexTokenPair) public returns (address) {
        require(dexFeedAddress[dexTokenPair] == address(0), "already created");
        address feedAddr = dexFeedFactory.create(underlying, stable, dexTokenPair);
        dexFeedAddress[dexTokenPair] = feedAddr;

        dexFeedAddresses.push(dexTokenPair);
        emit CreateDexFeed(feedAddr, msg.sender);
        return feedAddr;
    }

    function listDexFeedAddrs(uint offset, uint range) external view returns (address[] memory) {
        address[] memory feedAddrs;
        uint i_idx = 0;
        for (uint i = offset; i < range; i++) {
            feedAddrs[i_idx] = dexFeedAddresses[i];
            i_idx++;
        }
        return feedAddrs;
    }

    function totalDexFeedAddrs() external view returns (uint) {
        return dexFeedAddresses.length;
    }

    function getDexFeedAddress(address dexTokenPair) external view returns (address)  {
        return dexFeedAddress[dexTokenPair];
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
        (IOptionsExchange.OptionData memory opt, string memory symbol) =
            createOptionInMemory(udlFeed, optType, strike, maturity);
        (_tk) = writeOptionsInternal(opt, symbol, volume, to);
        ensureFunds(msg.sender);
    }

    function writeCovered(
        address udlFeed,
        uint volume,
        uint strike, 
        uint maturity,
        address to
    )
        external 
        returns (address _tk)
    {
        (IOptionsExchange.OptionData memory opt, string memory symbol) =
            createOptionInMemory(udlFeed, IOptionsExchange.OptionType.CALL, strike, maturity);
        _tk = tokenAddress[symbol];

        if (_tk == address(0)) {
            _tk = createSymbol(opt.udlFeed, IOptionsExchange.OptionType.CALL, strike, maturity);
        }
        
        address underlying = getUnderlyingAddr(opt);
        require(underlying != address(0), "underlying token not set");
        IERC20(underlying).safeTransferFrom(msg.sender, address(vault), volume);
        vault.lock(msg.sender, _tk, volume);

        writeOptionsInternal(opt, symbol, volume, to);
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

    function release(address owner, uint udl, uint coll) external {

        OptionToken tk = OptionToken(msg.sender);
        require(tokenAddress[tk.symbol()] == msg.sender, "unauthorized release");

        IOptionsExchange.OptionData memory opt = options[msg.sender];

        if (udl > 0) {
            vault.release(owner,  msg.sender, opt.udlFeed, udl);
        }
        
        if (coll > 0) {
            uint c = collateral[owner];
            collateral[owner] = c.sub(
                MoreMath.min(c, IBaseCollateralManager(settings.getUdlCollateralManager(opt.udlFeed)).calcCollateral(opt, coll))
            );
        }
    }

    function cleanUp(address owner, address _tk) public {

        OptionToken tk = OptionToken(_tk);

        if (tk.balanceOf(owner) == 0 && tk.writtenVolume(owner) == 0) {
            Arrays.removeItem(book[owner], _tk);
        }
    }

    function liquidateExpired(address _tk, address[] calldata owners) external {
        IBaseCollateralManager(settings.getUdlCollateralManager(options[_tk].udlFeed)).liquidateExpired(_tk, owners);
    }

    function liquidateOptions(address _tk, address owner) public returns (uint value) {
        value = IBaseCollateralManager(settings.getUdlCollateralManager(options[_tk].udlFeed)).liquidateOptions(_tk, owner);
    }

    function calcSurplus(address owner) public view returns (uint) {
        
        uint coll = collateralManager.calcCollateral(owner, true); // multi udl feed refs
        uint bal = creditProvider.balanceOf(owner);
        if (bal >= coll) {
            return bal.sub(coll);
        }
        return 0;
    }

    function setCollateral(address owner) external {
        /* UNUSED IN ANY CONTRACTS, DOES THIS NEED TO BE AN INCENTIVIZED FUNCTION */

        collateral[owner] = collateralManager.calcCollateral(owner, true); // multi udl feed refs
    }

    function calcCollateral(address owner, bool is_regular) public view returns (uint) {
        return collateralManager.calcCollateral(owner, is_regular); // multi udl feed refs
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
        return IBaseCollateralManager(settings.getUdlCollateralManager(opt.udlFeed)).calcCollateral(opt, volume);
    }

    function calcExpectedPayout(address owner) external view returns (int payout) {
        payout = collateralManager.calcExpectedPayout(owner); // multi udl feed refs
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
        return IBaseCollateralManager(settings.getUdlCollateralManager(opt.udlFeed)).calcIntrinsicValue(opt);
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
            uint[] memory uncovered,
            int[] memory iv
        )
    {
        tokens = book[owner];
        holding = new uint[](tokens.length);
        written = new uint[](tokens.length);
        uncovered = new uint[](tokens.length);
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
            uncovered[i] = tk.uncoveredVolume(owner);
            iv[i] = IBaseCollateralManager(settings.getUdlCollateralManager(opt.udlFeed)).calcIntrinsicValue(opt);
        }
    }

    function ensureFunds(address owner) private view {
        require(
            creditProvider.balanceOf(owner) >= collateral[owner],
            "insufficient collateral"
        );
    }

    function writeOptionsInternal(
        IOptionsExchange.OptionData memory opt,
        string memory symbol,
        uint volume,
        address to
    )
        private 
        returns (address _tk)
    {
        ensureFeedIsAlowed(opt.udlFeed);
        require(volume > 0, "invalid volume");
        require(opt.maturity > settings.exchangeTime(), "invalid maturity");

        _tk = tokenAddress[symbol];
        if (_tk == address(0)) {
            _tk = createSymbol(opt.udlFeed, opt._type, opt.strike, opt.maturity);
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
        
        uint v = MoreMath.min(volume, tk.uncoveredVolume(msg.sender));
        if (v > 0) {
            collateral[msg.sender] = collateral[msg.sender].add(
                IBaseCollateralManager(settings.getUdlCollateralManager(opt.udlFeed)).calcCollateral(opt, v)
            );
        }

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

    function getUdlPrice(IOptionsExchange.OptionData memory opt) private view returns (int answer) {

        if (opt.maturity > settings.exchangeTime()) {
            (,answer) = UnderlyingFeed(opt.udlFeed).getLatestPrice();
        } else {
            (,answer) = UnderlyingFeed(opt.udlFeed).getPrice(opt.maturity);
        }
    }

    function getUnderlyingAddr(IOptionsExchange.OptionData memory opt) private view returns (address) {
        return UnderlyingFeed(opt.udlFeed).getUnderlyingAddr();
    }

    function incrementRoundDexAgg(address dexAggAddr) incentivized external {
        // this is needed to provide data for UnderlyingFeed that originate from a dex
        require(settings.checkDexAggIncentiveBlacklist(dexAggAddr) == false, "blacklisted for incentives");
        DEXAggregatorV1(dexAggAddr).incrementRound();
    }

    function prefetchSample(address udlFeed) incentivized external {
        require(settings.checkUdlIncentiveBlacklist(udlFeed) == false, "blacklisted for incentives");
        UnderlyingFeed(udlFeed).prefetchSample();
    }

    function prefetchDailyPrice(address udlFeed, uint roundId) incentivized external {
        require(settings.checkUdlIncentiveBlacklist(udlFeed) == false, "blacklisted for incentives");
        UnderlyingFeed(udlFeed).prefetchDailyPrice(roundId);
    }

    function prefetchDailyVolatility(address udlFeed, uint timespan) incentivized external {
        require(settings.checkUdlIncentiveBlacklist(udlFeed) == false, "blacklisted for incentives");
        UnderlyingFeed(udlFeed).prefetchDailyVolatility(timespan);
    }

    modifier incentivized() {
        uint256 startGas = gasleft();

        _;
        
        uint256 gasUsed = startGas - gasleft();
        address[] memory tokens = settings.getAllowedTokens();

        uint256 creditingValue = settings.getBaseIncentivisation();        
        creditProvider.processIncentivizationPayment(msg.sender, creditingValue);
        emit IncentiveReward(msg.sender, creditingValue);    
    }

    function ensureFeedIsAlowed(address udlFeed) private view {
        
        require(settings.getUdlFeed(udlFeed) > 0, "feed not allowed");
    }
}
