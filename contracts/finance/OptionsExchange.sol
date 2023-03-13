pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/IBaseCollateralManager.sol";
import "../interfaces/IUnderlyingVault.sol";
import "../interfaces/IOptionToken.sol";
import "../interfaces/ILinearLiquidityPoolFactory.sol";
import "../interfaces/IDEXFeedFactory.sol";
import "../interfaces/IOptionTokenFactory.sol";
import "../interfaces/external/canto/ITurnstile.sol";

import "../utils/Arrays.sol";
import "../utils/Convert.sol";
import "../utils/ERC20.sol"; //issues with verifying and ERC20 that can reference other ERC20
import "../utils/MoreMath.sol";
import "../utils/SafeCast.sol";
import "../utils/SafeERC20.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";

contract OptionsExchange is ERC20, ManagedContract {

    using SafeCast for uint;
    using SafeERC20 for IERC20_2;
    using SafeMath for uint;
    using SignedSafeMath for int;
    
    IUnderlyingVault private vault;
    IProtocolSettings private settings;
    ICreditProvider private creditProvider;
    IDEXFeedFactory private dexFeedFactory;
    IBaseCollateralManager private collateralManager;
    address private pendingExposureRouterAddr;

    IOptionTokenFactory private optionTokenFactory;
    ILinearLiquidityPoolFactory private poolFactory;

    mapping(address => uint) public collateral;

    mapping(address => IOptionsExchange.OptionData) private options;
    mapping(address => IOptionsExchange.FeedData) private feeds;
    mapping(address => address[]) private book;

    mapping(string => address) private poolAddress;
    mapping(string => address) private tokenAddress;
    mapping(address => address) private dexFeedAddress;

    uint private _volumeBase;

    string private constant _name = "DeFi Options DAO Dollar";
    string private constant _symbol = "DODv2-DODD";

    string[] public poolSymbols;
    
    event WithdrawTokens(address indexed from, uint value);
    event CreatePool(address indexed token, address indexed sender);
    event CreateSymbol(address indexed token, address indexed sender);
    event CreateDexFeed(address indexed feed, address indexed sender);

    event WriteOptions(
        address indexed token,
        address indexed issuer,
        address indexed onwer,
        uint volume
    );

    constructor() ERC20(_name) public {
        
    }

    function initialize(Deployer deployer) override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        optionTokenFactory = IOptionTokenFactory(deployer.getContractAddress("OptionTokenFactory"));
        poolFactory  = ILinearLiquidityPoolFactory(deployer.getContractAddress("LinearLiquidityPoolFactory"));
        collateralManager = IBaseCollateralManager(deployer.getContractAddress("CollateralManager"));
        vault = IUnderlyingVault(deployer.getContractAddress("UnderlyingVault"));        
        ITurnstile(0xEcf044C5B4b867CFda001101c617eCd347095B44).assign(
            ITurnstile(0xEcf044C5B4b867CFda001101c617eCd347095B44).register(address(settings))
        );
        pendingExposureRouterAddr = deployer.getContractAddress("PendingExposureRouter");

        _volumeBase = 1e18;
    }

    function volumeBase() external view returns (uint) {
        return _volumeBase;
    }

    function name() override external view returns (string memory) {
        return _name;
    }

    function symbol() override external view returns (string memory) {
        return _symbol;
    }

    function totalSupply() override public view returns (uint) {
        return creditProvider.getTotalBalance();
    }

    function depositTokens(address to, address token, uint value) public {

        IERC20_2(token).safeTransferFrom(msg.sender, address(creditProvider), value);
        creditProvider.addBalance(to, token, value);
    }

    function balanceOf(address owner) override public view returns (uint) {

        return creditProvider.balanceOf(owner);
    }

    function transfer(address to, uint value) override external returns (bool) {
        creditProvider.transferBalance(msg.sender, to, value);
        ensureFunds(msg.sender);
        emitTransfer(msg.sender, to, value);
        return true;
    }


    function transferFrom(address from, address to, uint value) override public returns (bool) {

        uint allw = allowed[from][msg.sender];
        if (allw >= value) {
            allowed[from][msg.sender] = allw.sub(value);
        } else {
            creditProvider.ensureCaller(msg.sender);
        }
        creditProvider.transferBalance(from, to, value);
        ensureFunds(from);

        emitTransfer(from, to, value);
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

    function withdrawTokens(address[] calldata tokensInOrder, uint[] calldata amountsOutInOrder) external {

        uint value;
        for (uint i = 0; i < tokensInOrder.length; i++) {
            value = value.add(amountsOutInOrder[i]);
        }
        
        require(value <= calcSurplus(msg.sender), "insufficient surplus");
        creditProvider.withdrawTokens(msg.sender, value, tokensInOrder, amountsOutInOrder);
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
        require(settings.getUdlFeed(udlFeed) > 0, "feed not allowed");
        (IOptionsExchange.OptionData memory opt, string memory symbol) = createOptionInMemory(udlFeed, optType, strike, maturity);

        require(tokenAddress[symbol] == address(0), "already created");
        tk = optionTokenFactory.create(symbol, udlFeed);
        tokenAddress[symbol] = tk;
        options[tk] = opt;

        UnderlyingFeed feed = UnderlyingFeed(udlFeed);
        uint vol = feed.getDailyVolatility(settings.getVolatilityPeriod());
        feeds[udlFeed] = IOptionsExchange.FeedData(
            feed.calcLowerVolatility(uint(vol)).toUint120(),
            feed.calcUpperVolatility(uint(vol)).toUint120()
        );

        emit CreateSymbol(tk, msg.sender);
    }

    function createPool(string calldata nameSuffix, string calldata symbolSuffix) external returns (address pool) {

        require(poolAddress[symbolSuffix] == address(0), "already created");
        pool = poolFactory.create(nameSuffix, symbolSuffix);
        poolAddress[symbolSuffix] = pool;
        creditProvider.insertPoolCaller(pool);

        poolSymbols.push(symbolSuffix);
        emit CreatePool(pool, msg.sender);
        return pool;
    }

    function totalPoolSymbols() external view returns (uint) {
        return poolSymbols.length;
    }

    function getPoolAddress(string calldata poolSymbol) external view returns (address)  {
        return poolAddress[poolSymbol];
    }

    function createDexFeed(address underlying, address stable, address dexTokenPair) external returns (address) {
        require(dexFeedAddress[dexTokenPair] == address(0), "already created");
        address feedAddr = dexFeedFactory.create(underlying, stable, dexTokenPair);
        dexFeedAddress[dexTokenPair] = feedAddr;

        emit CreateDexFeed(feedAddr, msg.sender);
        return feedAddr;
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
            MoreMath.toString(maturity),
            "-",
            Address.toAsciiString(udlFeed)
        ));
    }

    function openExposure(
        IOptionsExchange.OpenExposureInputs memory oEi,
        address to
    ) public {
        /*require(
            (oEi.symbols.length == oEi.volume.length)  && 
            (oEi.symbols.length == oEi.isShort.length) && 
            (oEi.symbols.length == oEi.isCovered.length) && 
            (oEi.symbols.length == oEi.poolAddrs.length) && 
            (oEi.symbols.length == oEi.paymentTokens.length), 
            "array mismatch"
        );*/

        IOptionsExchange.OpenExposureVars memory oEx;

        // BIG QUESTION not sure if run time gas requirements will allow for this
            //- calc collateral gas question
            //- gas cost of multiple buy/sell txs from pool, maybe need optimized function for pool
        // validate that all the symbols exist, pool has prices, revert if not
        // make all the options buys/sells
        // compute collateral reqirements with uncovred volumes

        oEx._tokens = new address[](oEi.symbols.length);
        oEx._uncovered = new uint[](oEi.symbols.length);
        oEx._holding = new uint[](oEi.symbols.length);

        address recipient = msg.sender;

        //if msg.sender is pending order router, need to set proper recipient of positions
        if(pendingExposureRouterAddr == msg.sender) {
            recipient = to;
        }

        for (uint i=0; i< oEi.symbols.length; i++) {
            oEx = getOpenExposureInternalArgs(i, oEx, oEi);
            require(tokenAddress[oEx.symbol] != address(0), "symbol not available");
            oEx._tokens[i] = tokenAddress[oEx.symbol];
            IGovernableLiquidityPool pool = IGovernableLiquidityPool(oEx.poolAddr);
            uint _price;    
            if (oEi.isShort[i] == true) {
                //sell options
                if (oEx.vol > 0) {
                    openExposureInternal(oEx.symbol, oEx.isCovered, oEx.vol, to, recipient);
                    if (msg.sender == oEx.poolAddr){
                        //if the pool is the one writing the option to a user, transfer from exchange to user
                        IERC20_2(oEx._tokens[i]).transfer(to, oEx.vol);
                    } else {
                        //this will credit exchange addr that needs to be transfered the seller
                        (_price,) = pool.queryBuy(oEx.symbol, false);
                        IERC20_2(oEx._tokens[i]).approve(address(pool), oEx.vol);
                        pool.sell(oEx.symbol, _price, oEx.vol);
                    }
                    //if not covered option
                    if (oEx.isCovered == false) {
                        oEx._uncovered[i] = oEx.vol;
                    }
                }
            } else {
                // buy options
                if (oEx.vol > 0) {
                    (_price,) = pool.queryBuy(oEx.symbol, true);
                    pool.buy(oEx.symbol, _price, oEx.vol, oEi.paymentTokens[i]);
                    
                    oEx._holding[i] = oEx.vol;
                }
            }

            if ((msg.sender == oEx.poolAddr) && (oEi.isShort[i] == true)) {
                //this is handled by pool contract
            } else {
                creditProvider.transferBalance(
                    address(this),
                    (oEi.isShort[i] == true) ? recipient : oEx.poolAddr, 
                    _price.mul(oEx.vol).div(_volumeBase)
                );
            }
            
        }

        //NOTE: MAY NEED TO ONLY COMPUTE THE ONES WRITTEN/BOUGHT HERE FOR GAS CONSTRAINTS
        collateral[recipient] = collateral[recipient].add(
            collateralManager.calcNetCollateral(oEx._tokens, oEx._uncovered, oEx._holding, true)
        );
        ensureFunds(recipient);
    }

    function getOpenExposureInternalArgs(uint index, IOptionsExchange.OpenExposureVars memory oEx, IOptionsExchange.OpenExposureInputs memory oEi) private pure returns (IOptionsExchange.OpenExposureVars memory) {
        oEx.symbol= oEi.symbols[index];
        oEx.vol = oEi.volume[index];
        oEx.isCovered = oEi.isCovered[index];
        oEx.poolAddr = oEi.poolAddrs[index];

        return oEx;
    }

    function openExposureInternal(
        string memory symbol,
        bool isCovered,
        uint volume,
        address to,
        address recipient
    ) private {
        address _tk = tokenAddress[symbol];
        IOptionToken tk = IOptionToken(_tk);

        if (tk.writtenVolume(recipient) == 0 && tk.balanceOf(recipient) == 0) {
            book[recipient].push(_tk);
        }


        if (msg.sender != to && tk.writtenVolume(to) == 0 && tk.balanceOf(to) == 0) {
            book[to].push(_tk);
        }

        //mint to exchange, then send pool (or send to user)
        tk.issue(recipient, address(this), volume);
        if (isCovered == true) {
            //write covered
            address underlying = UnderlyingFeed(
                options[_tk].udlFeed
            ).getUnderlyingAddr();
            IERC20_2(underlying).safeTransferFrom(
                msg.sender,
                address(vault), 
                Convert.from18DecimalsBase(underlying, volume)
            );
            vault.lock(recipient, _tk, volume);
        }
        emit WriteOptions(_tk, recipient, to, volume);
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
        IOptionToken tk = IOptionToken(msg.sender);
        
        if (tk.writtenVolume(from) == 0 && tk.balanceOf(from) == 0) {
            Arrays.removeItem(book[from], msg.sender);
        }

        if (tk.writtenVolume(to) == 0 && tk.balanceOf(to) == value) {
            book[to].push(msg.sender);
        }

        ensureFunds(from);
    }

    function release(address owner, uint udl, uint coll) external {

        IOptionToken tk = IOptionToken(msg.sender);
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

        IOptionToken tk = IOptionToken(_tk);

        if (tk.balanceOf(owner) == 0 && tk.writtenVolume(owner) == 0) {
            Arrays.removeItem(book[owner], _tk);
        }
    }

    function calcSurplus(address owner) public view returns (uint) {
        
        uint coll = calcCollateral(owner, true); // multi udl feed refs
        uint bal = balanceOf(owner);
        if (bal >= coll) {
            return bal.sub(coll);
        }
        return 0;
    }

    function setCollateral(address owner) external {
        collateral[owner] = calcCollateral(owner, true); // multi udl feed refs
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
    
    function calcIntrinsicValue(address _tk) external view returns (int) {
        IOptionsExchange.OptionData memory opt = options[_tk];
        return IBaseCollateralManager(settings.getUdlCollateralManager(opt.udlFeed)).calcIntrinsicValue(options[_tk]);
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

    function resolveToken(string calldata symbol) external view returns (address) {
        
        address addr = tokenAddress[symbol];
        require(addr != address(0), "token not found");
        return addr;
    }

    function burn(address owner, uint value, address _tk) external {
        IOptionToken(_tk).burn(owner, value);
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
            int[] memory iv,
            address[] memory underlying
        )
    {
        tokens = book[owner];
        holding = new uint[](tokens.length);
        written = new uint[](tokens.length);
        uncovered = new uint[](tokens.length);
        iv = new int[](tokens.length);
        underlying = new address[](tokens.length);

        for (uint i = 0; i < tokens.length; i++) {
            IOptionToken tk = IOptionToken(tokens[i]);
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
            underlying[i] = UnderlyingFeed(opt.udlFeed).getUnderlyingAddr();

        }
    }

    function ensureFunds(address owner) private view {
        require(
            balanceOf(owner) >= collateral[owner],
            "insufficient collateral"
        );
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

    function getOptionSymbol(IOptionsExchange.OptionData memory opt) public view returns (string memory symbol) {    
        symbol = getOptionSymbol(
            opt.udlFeed,
            opt._type,
            opt.strike,
            opt.maturity
        );
    }
}
