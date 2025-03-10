pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/TimeProvider.sol";
import "../interfaces/IProposal.sol";
import "../interfaces/IGovToken.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/IUnderlyingVault.sol";
import "../interfaces/IBaseCollateralManager.sol";
import "../interfaces/IUnderlyingCreditToken.sol";
import "../interfaces/IUnderlyingCreditProvider.sol";
import "../interfaces/IUnderlyingCreditTokenFactory.sol";
import "../interfaces/IUnderlyingCreditProviderFactory.sol";
import "../utils/Arrays.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeERC20.sol";
import "./ProposalsManager.sol";
import "./ProposalWrapper.sol";

contract ProtocolSettings is ManagedContract {

    using SafeMath for uint;
    using SafeERC20 for IERC20_2;

    struct Rate {
        uint value;
        uint base;
        uint date;
    }

    TimeProvider private time;
    IGovToken private govToken;
    ICreditProvider private creditProvider;
    ProposalsManager private manager;
    IUnderlyingVault private vault;
    IUnderlyingCreditTokenFactory private underlyingCreditTokenFactory;
    IUnderlyingCreditProviderFactory private underlyingCreditProviderFactory;

    mapping(address => int) private underlyingFeeds;
    mapping(address => uint256) private dexOracleTwapPeriod;
    mapping(address => Rate) private tokenRates;
    mapping(address => bool) private poolBuyCreditTradeable;
    mapping(address => bool) private poolSellCreditTradeable;
    mapping(address => bool) private udlIncentiveBlacklist;
    mapping(address => bool) private hedgingManager;
    mapping(address => bool) private rehypothicationManager;
    mapping(address => bool) private poolCustomLeverage;
    mapping(address => bool) private dexAggIncentiveBlacklist;
    mapping(address => address) private udlCollateralManager;

    mapping(address => Rate[]) private udlCreditInterestRates;
    mapping(address => Rate[]) private udlDebtInterestRates;

    mapping(address => mapping(address => address[])) private paths;

    address[] private tokens;

    Rate[] private debtInterestRates;
    Rate[] private creditInterestRates;
    Rate private processingFee;
    uint private volatilityPeriod;

    bool private hotVoting;
    Rate private minShareForProposal;
    uint private circulatingSupply;

    uint private baseIncentivisation = 10e18;
    uint private maxIncentivisation = 100e18;

    uint private creditTimeLock = 60 * 60 * 24; // 24h withdrawl time lock for 
    uint private minCreditTimeLock = 60 * 60 * 2; // 2h min withdrawl time lock
    uint private maxCreditTimeLock = 60 * 60 * 48; // 48h min withdrawl time lock

    uint256 private _twapPeriodMax = 60 * 60 * 24; // 1 day
    uint256 private _twapPeriodMin = 60 * 60 * 2; // 2 hours

    address private swapRouter;
    address private swapToken;
    address private baseCollateralManagerAddr;
    Rate private swapTolerance;

    uint private MAX_SUPPLY;
    uint private MAX_UINT;

    event SetCirculatingSupply(address sender, uint supply);
    event SetTokenRate(address sender, address token, uint v, uint b);
    event SetAllowedToken(address sender, address token, uint v, uint b);
    event RemoveAllowedToken(address sender, address token);
    event SetMinShareForProposal(address sender, uint s, uint b);
    event SetDebtInterestRate(address sender, uint i, uint b);
    event SetCreditInterestRate(address sender, uint i, uint b);
    event SetUnderlyingCreditInterestRate(address sender, uint i, uint b);
    event SetUnderlyingDebtInterestRate(address sender, uint i, uint b);
    event SetProcessingFee(address sender, uint f, uint b);
    event SetUdlFeed(address sender, address addr, int v);
    event SetVolatilityPeriod(address sender, uint _volatilityPeriod);
    event SetSwapRouterInfo(address sender, address router, address token);
    event SetSwapRouterTolerance(address sender, uint r, uint b);
    event SetSwapPath(address sender, address from, address to);
    event TransferBalance(address sender, address to, uint amount);
    event TransferGovToken(address sender, address to, uint amount);
    
    constructor(bool _hotVoting) public {
        
        hotVoting = _hotVoting;
    }
    
    function initialize(Deployer deployer) override internal {

        time = TimeProvider(deployer.getContractAddress("TimeProvider"));
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        manager = ProposalsManager(deployer.getContractAddress("ProposalsManager"));
        govToken = IGovToken(deployer.getContractAddress("GovToken"));
        baseCollateralManagerAddr = deployer.getContractAddress("CollateralManager");
        vault = IUnderlyingVault(deployer.getContractAddress("UnderlyingVault"));
        underlyingCreditTokenFactory = IUnderlyingCreditTokenFactory(deployer.getContractAddress("UnderlyingCreditTokenFactory"));
        underlyingCreditProviderFactory = IUnderlyingCreditProviderFactory(deployer.getContractAddress("UnderlyingCreditProviderFactory"));

        MAX_UINT = uint(-1);

        MAX_SUPPLY = 100e6 * 1e18;

        hotVoting = ProtocolSettings(getImplementation()).isHotVotingAllowed();

        minShareForProposal = Rate( // 1%
            100,
            10000, 
            MAX_UINT
        );

        debtInterestRates.push(Rate( // 25% per year
            10000254733325807, 
            10000000000000000, 
            MAX_UINT
        ));

        creditInterestRates.push(Rate( // 15% per year
            10000155696689545, 
            10000000000000000,
            MAX_UINT
        ));

        processingFee = Rate( // no fees
            0,
            10000000000000000, 
            MAX_UINT
        );

        volatilityPeriod = 90 days;
    }

    function getCirculatingSupply() external view returns (uint) {

        return circulatingSupply;
    }

    function setCirculatingSupply(uint supply) external {

        require(supply > circulatingSupply, "cannot decrease supply");
        require(supply <= MAX_SUPPLY, "max supply surpassed");

        ensureWritePrivilege();
        circulatingSupply = supply;

        emit SetCirculatingSupply(msg.sender, supply);
    }

    function getTokenRate(address token) external view returns (uint v, uint b) {

        v = tokenRates[token].value;
        b = tokenRates[token].base;
    }

    function setTokenRate(address token, uint v, uint b) external {
        /*

            "b" corresponds to token decimal normalization parameter such that the decimals the stablecoin represents is 18 on the exchange for example:
                A stable coin with 6 decimals will need b set to 1e12, relative to one that has 18 decimals which will be set to just 1

        */

        require(v != 0 && b != 0, "invalid parameters");
        ensureWritePrivilege();
        tokenRates[token] = Rate(v, b, MAX_UINT);

        emit SetTokenRate(msg.sender, token, v, b);
    }

    function getAllowedTokens() external view returns (address[] memory) {

        return tokens;
    }

    function setAllowedToken(address token, uint v, uint b) external {

        require(token != address(0), "invalid token address");
        require(v != 0 && b != 0, "invalid parameters");
        ensureWritePrivilege();
        if (tokenRates[token].value != 0) {
            Arrays.removeItem(tokens, token);
        }
        tokens.push(token);
        tokenRates[token] = Rate(v, b, MAX_UINT);

        emit SetAllowedToken(msg.sender, token, v, b);
    }

    function removedAllowedToken(address token) external {

        require(token != address(0), "invalid token address");
        ensureWritePrivilege();
        if (tokenRates[token].value != 0) {
            Arrays.removeItem(tokens, token);
            tokenRates[token] = Rate(0, 0, 0);
        }

        emit RemoveAllowedToken(msg.sender, token);
    }

    function isHotVotingAllowed() external view returns (bool) {

        // IMPORTANT: hot voting should be set to 'false' for mainnet deployment
        return hotVoting;
    }

    function suppressHotVoting() external {

        // no need to ensure write privilege. can't be undone.
        hotVoting = false;
    }

    function getMinShareForProposal() external view returns (uint v, uint b) {
        
        v = minShareForProposal.value;
        b = minShareForProposal.base;
    }

    function setMinShareForProposal(uint s, uint b) external {
        
        require(b / s <= 100, "minimum share too low");
        validateFractionLTEOne(s, b);
        ensureWritePrivilege();
        minShareForProposal = Rate(s, b, MAX_UINT);

        emit SetMinShareForProposal(msg.sender, s, b);
    }

    function getDebtInterestRate() external view returns (uint v, uint b, uint d) {
        
        uint len = debtInterestRates.length;
        Rate memory r = debtInterestRates[len - 1];
        v = r.value;
        b = r.base;
        d = r.date;
    }

    function applyDebtInterestRate(uint value, uint date) external view returns (uint) {
        
        return applyRates(debtInterestRates, value, date);
    }

    function setDebtInterestRate(uint i, uint b) external {
        
        validateFractionGTEOne(i, b);
        ensureWritePrivilege();
        debtInterestRates[debtInterestRates.length - 1].date = time.getNow();
        debtInterestRates.push(Rate(i, b, MAX_UINT));

        emit SetDebtInterestRate(msg.sender, i, b);
    }

    function applyUnderlyingDebtInterestRate(uint value, uint date, address udlAsset) external view returns (uint) {

        if (udlDebtInterestRates[udlAsset].length > 0) {
            return applyRates(udlDebtInterestRates[udlAsset], value, date);
        } else {
            // default to exchange stablecoin credit rate policy
            return applyRates(debtInterestRates, value, date);
        }
    }

    function getUnderlyingDebtInterestRate(uint date, address udlAsset) external view returns (uint v, uint b, uint d) {
        
        Rate memory r = getRate(udlDebtInterestRates[udlAsset], date);
        v = r.value;
        b = r.base;
        d = r.date;
    }

    function setUnderlyingDebtnterestRate(uint i, uint b, address udlAsset) external {
        
        validateFractionGTEOne(i, b);
        ensureWritePrivilege();
        udlDebtInterestRates[udlAsset][udlDebtInterestRates[udlAsset].length - 1].date = time.getNow();
        udlDebtInterestRates[udlAsset].push(Rate(i, b, MAX_UINT));

        emit SetUnderlyingDebtInterestRate(msg.sender, i, b);
    }

    function getCreditInterestRate() external view returns (uint v, uint b, uint d) {
        
        uint len = creditInterestRates.length;
        Rate memory r = creditInterestRates[len - 1];
        v = r.value;
        b = r.base;
        d = r.date;
    }

    function applyCreditInterestRate(uint value, uint date) external view returns (uint) {
        
        return applyRates(creditInterestRates, value, date);
    }

    function applyUnderlyingCreditInterestRate(uint value, uint date, address udlAsset) external view returns (uint) {

        if (udlCreditInterestRates[udlAsset].length > 0) {
            return applyRates(udlCreditInterestRates[udlAsset], value, date);
        } else {
            // default to exchange stablecoin credit rate policy
            return applyRates(creditInterestRates, value, date);
        }
    }

    function getCreditInterestRate(uint date) external view returns (uint v, uint b, uint d) {
        
        Rate memory r = getRate(creditInterestRates, date);
        v = r.value;
        b = r.base;
        d = r.date;
    }

    function setCreditInterestRate(uint i, uint b) external {
        
        validateFractionGTEOne(i, b);
        ensureWritePrivilege();
        creditInterestRates[creditInterestRates.length - 1].date = time.getNow();
        creditInterestRates.push(Rate(i, b, MAX_UINT));

        emit SetCreditInterestRate(msg.sender, i, b);
    }

    function getUnderlyingCreditInterestRate(uint date, address udlAsset) external view returns (uint v, uint b, uint d) {
        
        Rate memory r = getRate(udlCreditInterestRates[udlAsset], date);
        v = r.value;
        b = r.base;
        d = r.date;
    }

    function setUnderlyingCreditInterestRate(uint i, uint b, address udlAsset) external {
        
        validateFractionGTEOne(i, b);
        ensureWritePrivilege();
        udlCreditInterestRates[udlAsset][udlCreditInterestRates[udlAsset].length - 1].date = time.getNow();
        udlCreditInterestRates[udlAsset].push(Rate(i, b, MAX_UINT));

        emit SetUnderlyingCreditInterestRate(msg.sender, i, b);
    }

    function getProcessingFee() external view returns (uint v, uint b) {
        
        v = processingFee.value;
        b = processingFee.base;
    }

    function setProcessingFee(uint f, uint b) external {
        
        validateFractionLTEOne(f, b);
        ensureWritePrivilege();
        processingFee = Rate(f, b, MAX_UINT);

        emit SetProcessingFee(msg.sender, f, b);
    }

    function getUdlFeed(address addr) external view returns (int) {

        return underlyingFeeds[addr];
    }

    function setUdlFeed(address addr, int v) external {
        require(addr != address(0), "invalid feed address");

        bool success;
        uint i;
        int state_success_count = 0;

        //sucess bool true tests, revert imdeiately
        string[5] memory udlFunctionSignaturesNoArgs = [
            "symbol()",
            "getUnderlyingAddr()",
            "getPrivledgedPublisherKeeper()",
            "getUnderlyingAggAddr()",
            "getLatestPrice()"
        ];

        for(i=0;i<udlFunctionSignaturesNoArgs.length;i++){
            (success, ) = addr.call(
                abi.encodeWithSignature(
                    udlFunctionSignaturesNoArgs[i]
                )
            );
            require(success == true, "failed compat 1");
        }

        //sucess bool true tests, revert imdeiately
        string[5] memory udlFunctionSignaturesArgs = [
            "getPrice(uint256)",//seed with input -> 0
            "getDailyVolatility(uint256)",//seed with input -> volatilityPeriod
            "getDailyVolatilityCached(uint256)",//seed with input -> volatilityPeriod
            "calcLowerVolatility(uint256)", //seed with input->volatilityPeriod
            "calcUpperVolatility(uint256)" //seed with input->volatilityPeriod
        ];


        for(i=0;i<udlFunctionSignaturesArgs.length;i++){
            (success, ) = addr.call(
                abi.encodeWithSignature(
                    udlFunctionSignaturesArgs[i],
                    (i == 0) ? uint(0): volatilityPeriod
                )
            );
            require(success == true, udlFunctionSignaturesArgs[i]);
        }
        //sucess bool true tests, revert if all false
        string[3] memory udlFunctionSignaturesState = [
            "prefetchSample()",
            "prefetchDailyPrice(uint)",//seed with input -> 0
            "prefetchDailyVolatility(uint)" //seed with input -> volatilityPeriod
        ];
        for(i=0;i<udlFunctionSignaturesState.length;i++){
            if (i == 0) {
                (success, ) = addr.call(
                    abi.encodeWithSignature(
                        udlFunctionSignaturesState[i]
                    )
                );
            } else {
                (success, ) = addr.call(
                    abi.encodeWithSignature(
                        udlFunctionSignaturesState[i],
                        (i == 1) ? 0: volatilityPeriod
                    )
                );
            }
            if(success == true){
                state_success_count++;
            }
        }
        require(state_success_count > 0, "failed state compat");

        underlyingFeeds[addr] = v;
        udlIncentiveBlacklist[addr] = true;
        createUnderlyingCreditManagement(addr);

        emit SetUdlFeed(msg.sender, addr, v);
    }

    function setVolatilityPeriod(uint _volatilityPeriod) external {

        require(
            _volatilityPeriod > 30 days && _volatilityPeriod < 720 days,
            "invalid volatility period"
        );
        ensureWritePrivilege();
        volatilityPeriod = _volatilityPeriod;

        emit SetVolatilityPeriod(msg.sender, _volatilityPeriod);
    }

    function getVolatilityPeriod() external view returns(uint) {

        return volatilityPeriod;
    }

    function setSwapRouterInfo(address router, address token) external {
        
        require(router != address(0), "invalid router address");
        ensureWritePrivilege();
        swapRouter = router;
        swapToken = token;

        emit SetSwapRouterInfo(msg.sender, router, token);
    }

    function getSwapRouterInfo() external view returns (address router, address token) {

        router = swapRouter;
        token = swapToken;
    }

    function setSwapRouterTolerance(uint r, uint b) external {

        validateFractionGTEOne(r, b);
        ensureWritePrivilege();
        swapTolerance = Rate(r, b, MAX_UINT);

        emit SetSwapRouterTolerance(msg.sender, r, b);
    }

    function getSwapRouterTolerance() external view returns (uint r, uint b) {

        r = swapTolerance.value;
        b = swapTolerance.base;
    }

    function setSwapPath(address from, address to, address[] calldata path) external {

        require(from != address(0), "invalid 'from' address");
        require(to != address(0), "invalid 'to' address");
        require(path.length >= 2, "invalid swap path");
        ensureWritePrivilege();
        paths[from][to] = path;

        emit SetSwapPath(msg.sender, from, to);
    }

    function getSwapPath(address from, address to) external view returns (address[] memory path) {

        path = paths[from][to];
        if (path.length == 0) {
            path = new address[](2);
            path[0] = from;
            path[1] = to;
        }
    }

    function transferTokenBalance(address to, address tokenAddr, uint256 value) external {
        ensureWritePrivilege(true);
        if (value > 0) {
            IERC20_2(tokenAddr).safeTransfer(to, value);
        }
    }

    function transferBalance(address to, uint amount) external {
        
        uint total = creditProvider.totalTokenStock();
        require(total >= amount, "excessive amount");
        
        ensureWritePrivilege(true);

        creditProvider.transferBalance(address(this), to, amount);

        emit TransferBalance(msg.sender, to, amount);
    }

    function transferGovTokens(address to, uint amount) external {
        
        ensureWritePrivilege(true);

        govToken.transfer(to, amount);

        emit TransferGovToken(msg.sender, to, amount);
    }

    function applyRates(Rate[] storage rates, uint value, uint date) private view returns (uint) {
        
        Rate memory r;
        
        do {
            r = getRate(rates, date);
            uint dt = MoreMath.min(r.date, time.getNow()).sub(date).div(1 hours);
            if (dt > 0) {
                value = MoreMath.powAndMultiply(r.value, r.base, dt, value);
                date = r.date;
            }
        } while (r.date != MAX_UINT);

        return value;
    }

    function getRate(Rate[] storage rates, uint date) private view returns (Rate memory r) {
        
        uint len = rates.length;
        r = rates[len - 1];
        for (uint i = 0; i < len; i++) {
            if (date < rates[i].date) {
                r = rates[i];
                break;
            }
        }
    }

    /* CREDIT TOKEN SETTINGS */

    function getCreditWithdrawlTimeLock() external view returns (uint) {
        return creditTimeLock;
    }

    function updateCreditWithdrawlTimeLock(uint duration) external {
        ensureWritePrivilege();
        require(duration >= minCreditTimeLock && duration <= maxCreditTimeLock, "CDTK: outside of time lock range");
        creditTimeLock = duration;
    }

    /* POOL CREDIT SETTINGS */

    function setPoolBuyCreditTradable(address poolAddress, bool isTradable) external {
        ensureWritePrivilege();
        poolBuyCreditTradeable[poolAddress] = isTradable;
    }

    function checkPoolBuyCreditTradable(address poolAddress) external view returns (bool) {
        return poolBuyCreditTradeable[poolAddress];
    }

    function setPoolSellCreditTradable(address poolAddress, bool isTradable) external {
        ensureWritePrivilege();
        poolSellCreditTradeable[poolAddress] = isTradable;
    }

    function checkPoolSellCreditTradable(address poolAddress) external view returns (bool) {
        return poolSellCreditTradeable[poolAddress];
    }

    /* FEED INCENTIVES SETTINGS*/


    function setUdlIncentiveBlacklist(address udlAddr, bool isIncentivizable) external {
        ensureWritePrivilege();
        udlIncentiveBlacklist[udlAddr] = isIncentivizable;
    }

    function checkUdlIncentiveBlacklist(address udlAddr) external view returns (bool) {
        return udlIncentiveBlacklist[udlAddr];
    }

    function setDexAggIncentiveBlacklist(address dexAggAddress, bool isIncentivizable) external {
        ensureWritePrivilege();
        dexAggIncentiveBlacklist[dexAggAddress] = isIncentivizable;
    }

    function checkDexAggIncentiveBlacklist(address dexAggAddress) external view returns (bool) {
        return dexAggIncentiveBlacklist[dexAggAddress];
    }

    /* DEX ORACLE SETTINGS */

    function setDexOracleTwapPeriod(address dexOracleAddress, uint256 _twapPeriod) external {
        ensureWritePrivilege();
        require((_twapPeriod >= _twapPeriodMin) && (_twapPeriod <= _twapPeriodMax), "outside of twap bounds");
        dexOracleTwapPeriod[dexOracleAddress] = _twapPeriod;
    }

    function getDexOracleTwapPeriod(address dexOracleAddress) external view returns (uint256) {
        return dexOracleTwapPeriod[dexOracleAddress];
    }

    /* COLLATERAL MANAGER SETTINGS */

    function setUdlCollateralManager(address udlFeed, address ctlMngr) external {
        ensureWritePrivilege();
        require(underlyingFeeds[udlFeed] > 0, "feed not allowed");
        udlCollateralManager[udlFeed] = ctlMngr;
    }

    function getUdlCollateralManager(address udlFeed) external view returns (address) {
        return (udlCollateralManager[udlFeed] == address(0)) ? baseCollateralManagerAddr : udlCollateralManager[udlFeed];
    }

    /* INCENTIVIZATION STUFF */

    function setBaseIncentivisation(uint amount) external {
        ensureWritePrivilege();
        require(amount <= maxIncentivisation, "too high");
        baseIncentivisation = amount;
    }

    function getBaseIncentivisation() external view returns (uint) {
        return baseIncentivisation;
    }

    /* HEDGING MANAGER SETTINGS */

    function setAllowedHedgingManager(address hedgeMngr, bool val) external {
        ensureWritePrivilege();
        hedgingManager[hedgeMngr] = val;
    }

    function isAllowedHedgingManager(address hedgeMngr) external view returns (bool) {
        return hedgingManager[hedgeMngr];
    }

    function setAllowedCustomPoolLeverage(address poolAddr, bool val) external {
        ensureWritePrivilege();
        poolCustomLeverage[poolAddr] = val;
    }

    function isAllowedCustomPoolLeverage(address poolAddr) external view returns (bool) {
        return poolCustomLeverage[poolAddr];
    }

    /* REHYPOTHICATION MANAGER SETTINGS */

    function setAllowedRehypothicationManager(address rehyMngr, bool val) external {
        ensureWritePrivilege();
        rehypothicationManager[rehyMngr] = val;
    }

    function isAllowedRehypothicationManager(address rehyMngr) external view returns (bool) {
            return rehypothicationManager[rehyMngr];
    }

    function createUnderlyingCreditManagement(address udlFeed) private {
        //TODO: need to check how much gas is used to create two contracts

        address udlAsset = UnderlyingFeed(udlFeed).getUnderlyingAddr();

        if (udlAsset != address(0)) {
            address _uct = underlyingCreditTokenFactory.create(udlFeed);
            address _ucp = underlyingCreditProviderFactory.create(udlFeed);

            vault.setUnderlyingCreditProvider(udlAsset, _ucp);

            IUnderlyingCreditProvider(_ucp).initialize(_uct);
            IUnderlyingCreditToken(_uct).initialize(_ucp);
        }
    }

    /* underlying debt for stable swap */

    function swapUnderlyingDebtForStableDebt(address udlFeed, uint256 creditingValue) external {
        ensureWritePrivilege();
        IBaseCollateralManager(baseCollateralManagerAddr).debtSwap(udlFeed, creditingValue);
    }


    function getPoolCreditTradeable(address poolAddr) external view returns (uint){
        if((poolBuyCreditTradeable[poolAddr] == true) || (poolSellCreditTradeable[poolAddr] == true)) {
            return creditProvider.totalTokenStock();
        } else {
            return creditProvider.balanceOf(poolAddr);
        }
    }


    function ensureWritePrivilege() private view {
        ensureWritePrivilege(false);
    }

    function ensureWritePrivilege(bool enforceProposal) private view {

        if (msg.sender != getOwner() || enforceProposal) {

            ProposalWrapper w = ProposalWrapper(manager.resolve(msg.sender));
            require(manager.isRegisteredProposal(msg.sender), "proposal not registered");
            require(w.isExecutionAllowed(), "execution not allowed");
        }
    }

    function validateFractionLTEOne(uint n, uint d) private pure {

        require(d > 0 && d >= n, "fraction should be less then or equal to one");
    }

    function validateFractionGTEOne(uint n, uint d) private pure {

        require(d > 0 && n >= d, "fraction should be greater than or equal to one");
    }

    function exchangeTime() external view returns (uint256) {
        return time.getNow();
    }
}