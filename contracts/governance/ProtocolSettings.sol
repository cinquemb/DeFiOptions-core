pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/TimeProvider.sol";
import "../interfaces/IProposal.sol";
import "../interfaces/IGovToken.sol";
import "../interfaces/ICreditProvider.sol";
import "../utils/Arrays.sol";
import "../utils/MoreMath.sol";
import "./ProposalsManager.sol";
import "./ProposalWrapper.sol";

contract ProtocolSettings is ManagedContract {

    using SafeMath for uint;

    struct Rate {
        uint value;
        uint base;
        uint date;
    }

    TimeProvider private time;
    IGovToken private govToken;
    ICreditProvider private creditProvider;
    ProposalsManager private manager;

    mapping(address => int) private underlyingFeeds;
    mapping(address => uint256) private dexOracleTwapPeriod;
    mapping(address => Rate) private tokenRates;
    mapping(address => bool) private poolBuyCreditTradeable;
    mapping(address => bool) private udlIncentiveBlacklist;
    mapping(address => bool) private rehypothecationManager;
    mapping(address => bool) private dexAggIncentiveBlacklist;
    mapping(address => address) private udlCollateralManager;

    mapping(address => mapping(address => address[])) private paths;

    address[] private tokens;

    Rate[] private debtInterestRates;
    Rate[] private creditInterestRates;
    Rate private processingFee;
    Rate private rehypothecationFee;
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
    event SetMinShareForProposal(address sender, uint s, uint b);
    event SetDebtInterestRate(address sender, uint i, uint b);
    event SetCreditInterestRate(address sender, uint i, uint b);
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

        creditInterestRates.push(Rate( // 5% per year
            10000055696689545, 
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

    function getRehypothecationFee() external view returns (uint v, uint b) {
        // charged at settlement
        
        v = rehypothecationFee.value;
        b = rehypothecationFee.base;
    }

    function setRehypothecationFee(uint f, uint b) external {
        
        validateFractionLTEOne(f, b);
        ensureWritePrivilege();
        rehypothecationFee = Rate(f, b, MAX_UINT);

        emit SetRehypothecationFee(msg.sender, f, b);
    }

    function getUdlFeed(address addr) external view returns (int) {

        return underlyingFeeds[addr];
    }

    function setUdlFeed(address addr, int v) external {

        require(addr != address(0), "invalid feed address");
        ensureWritePrivilege();
        underlyingFeeds[addr] = v;

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

    /* REHYPOTHECICATION MANAGER SETTINGS */

    function setAllowedRehypothecationManager(address rehypoMngr, bool val) external {
        ensureWritePrivilege();
        rehypothecationManager[rehypoMngr] = val;
    }

    function isAllowedRehypothecationManager(address rehypoMngr) external view returns (bool) {
        return rehypothecationManager[rehypoMngr];
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