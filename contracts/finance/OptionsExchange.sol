pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../governance/ProtocolSettings.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/ILiquidityPool.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/IUnderlyingVault.sol";

import "../utils/Arrays.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeCast.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";
import "./OptionToken.sol";
import "./OptionTokenFactory.sol";
import "../feeds/DEXOracleFactory.sol";
import "../pools/LinearLiquidityPoolFactory.sol";

contract OptionsExchange is ManagedContract {

    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;
    
    IUnderlyingVault private vault;
    ProtocolSettings private settings;
    ICreditProvider private creditProvider;
    DEXOracleFactory private oracleFactory;
    ICollateralManager private collateralManager;

    OptionTokenFactory private optionTokenFactory;
    LinearLiquidityPoolFactory private poolFactory;

    mapping(address => uint) public collateral;
    mapping(address => IOptionsExchange.OptionData) private options;
    mapping(address => IOptionsExchange.FeedData) private feeds;
    mapping(address => address[]) private book;

    mapping(string => address) private poolAddress;
    mapping(string => address) private tokenAddress;
    mapping(address => string) private dexOracleAddress;

    uint private _volumeBase;

    string[] private poolSymbols;
    address[] private dexOracleAddresses;
    
    event RemovePoolSymbol(string symbolSuffix);
    event WithdrawTokens(address indexed from, uint value);
    event IncentiveReward(address indexed from, uint value);
    event CreatePool(address indexed token, address indexed sender);
    event CreateSymbol(address indexed token, address indexed sender);
    event CreateDexOracle(address indexed oracle, address indexed oracleAgg, address indexed sender);

    event WriteOptions(
        address indexed token,
        address indexed issuer,
        address indexed onwer,
        uint volume
    );

    function initialize(Deployer deployer) override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        optionTokenFactory = OptionTokenFactory(deployer.getContractAddress("OptionTokenFactory"));
        poolFactory  = LinearLiquidityPoolFactory(deployer.getContractAddress("LinearLiquidityPoolFactory"));
        collateralManager = ICollateralManager(deployer.getContractAddress("CollateralManager"));
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
        int excessCollateral = collateralManager.collateralSkew();

        t.transferFrom(msg.sender, address(creditProvider), value);

        /* 
            if shortage:
                deduct from creditited value;
                burn debt any debt on credit provider balance
            if excesss
                add to credited value;
        */        
        
        uint creditingValue = uint(int(value).sub(excessCollateral));
        creditProvider.addBalance(to, token, creditingValue);

        if (excessCollateral > 0){
            creditProvider.burnDebt(uint(excessCollateral)); 
        }
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
        (IOptionsExchange.OptionData memory opt, string memory symbol) =
            createOptionInMemory(udlFeed, optType, strike, maturity);

        require(tokenAddress[symbol] == address(0), "already created");
        tk = optionTokenFactory.create(symbol, udlFeed);
        tokenAddress[symbol] = tk;
        options[tk] = opt;
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

    function createDexOracle(address underlying, address stable, address dexTokenPair) public returns (address pool) {
        bytes32 memory dexTokenPairStr = bytes32((dexOracleAddress[dexTokenPair]);
        require(dexTokenPairStr.length == 0, "already created");
        (oracleAddr, aggAddr) = oracleFactory.create(underlying, stable, dexTokenPair);
        dexOracleAddress[dexTokenPair] = pool;// TODO: GET TOKEN PAIR NAME

        dexOracleAddresses.push(dexTokenPair);
        emit CreateDexOracle(oracleAddr, aggAddr, msg.sender);
    }

    function listPoolSymbols() external view returns (string memory available) {
        for (uint i = 0; i < poolSymbols.length; i++) {
            ILiquidityPool llp = ILiquidityPool(poolAddress[poolSymbols[i]]);
            if (llp.maturity() > settings.exchangeTime()) {
                available = listPoolSymbolHelper(available, poolSymbols[i]);
            }
        }
    }

    function listExpiredPoolSymbols() external view returns (string memory available) {
        for (uint i = 0; i < poolSymbols.length; i++) {
            ILiquidityPool llp = ILiquidityPool(poolAddress[poolSymbols[i]]);
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

        ILiquidityPool llp = ILiquidityPool(poolAddress[symbolSuffix]);
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
        IERC20(underlying).transferFrom(msg.sender, address(vault), volume);
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
                MoreMath.min(c, collateralManager.calcCollateral(opt, coll))
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

    function setCollateral(address owner) external {
        /* UNUSED IN ANY CONTRACTS, DOES THIS NEED TO BE AN INCENTIVIZED FUNCTION */

        collateral[owner] = collateralManager.calcCollateral(owner, true);
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
            iv[i] = collateralManager.calcIntrinsicValue(opt);
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
        require(settings.getUdlFeed(opt.udlFeed) > 0, "feed not allowed");
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
                collateralManager.calcCollateral(opt, v)
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

    function getUdlPrice(IOptionsExchange.OptionData memory opt) internal view returns (int answer) {

        if (opt.maturity > settings.exchangeTime()) {
            (,answer) = UnderlyingFeed(opt.udlFeed).getLatestPrice();
        } else {
            (,answer) = UnderlyingFeed(opt.udlFeed).getPrice(opt.maturity);
        }
    }

    function getUnderlyingAddr(IOptionsExchange.OptionData memory opt) private view returns (address) {
        
        return UnderlyingFeed(opt.udlFeed).getUnderlyingAddr();
    }

    function prefetchSample(address udlFeed) incentivized external {
        UnderlyingFeed(udlFeed).prefetchSample();
    }

    function prefetchDailyPrice(address udlFeed, uint roundId) incentivized external {
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
            use gas (chainlink) price oracle to multiply current gas price by gas used, convert to $, debit exchange balance, fixed for now
        */

        uint256 creditingValue = 10e18;        
        creditProvider.processIncentivizationPayment(msg.sender, creditingValue);
        emit IncentiveReward(msg.sender, creditingValue);    
    }
}
