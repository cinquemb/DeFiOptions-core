pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../governance/ProtocolSettings.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ICreditToken.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";


contract CreditProvider is ManagedContract {

    using SafeMath for uint;
    using SignedSafeMath for int;
    
    ProtocolSettings private settings;
    ICreditToken private creditToken;

    mapping(address => uint) private balances;
    mapping(address => uint) private debts;
    mapping(address => uint) private debtsDate;
    mapping(address => uint) private callers;
    mapping(address => uint) private primeCallers;

    address private ctAddr;
    address private exchangeAddr;

    uint private _totalDebt;
    uint private _totalOwners;
    uint private _totalBalance;
    uint private _totalAccruedFees;


    event DepositTokens(address indexed to, address indexed token, uint value);

    event WithdrawTokens(address indexed from, address indexed token, uint value);

    event TransferBalance(address indexed from, address indexed to, uint value);

    event AccumulateDebt(address indexed to, uint value);

    event BurnDebt(address indexed from, uint value);

    event AccrueFees(address indexed from, uint value);

    function initialize(Deployer deployer) override internal {

        creditToken = ICreditToken(deployer.getContractAddress("CreditToken"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchangeAddr = deployer.getContractAddress("OptionsExchange");
        address vaultAddr = deployer.getContractAddress("UnderlyingVault");
        address collateralManagerAddr = deployer.getContractAddress("CollateralManager");
        
        callers[exchangeAddr] = 1;
        callers[address(settings)] = 1;
        callers[address(creditToken)] = 1;
        callers[vaultAddr] = 1;
        callers[collateralManagerAddr] = 1;

        primeCallers[exchangeAddr] = 1;
        primeCallers[address(settings)] = 1;
        primeCallers[address(creditToken)] = 1;
        primeCallers[vaultAddr] = 1;
        primeCallers[collateralManagerAddr] = 1;


        ctAddr = address(creditToken);
    }

    function totalTokenStock() external view returns (uint v) {

        address[] memory tokens = settings.getAllowedTokens();
        for (uint i = 0; i < tokens.length; i++) {
            (uint r, uint b) = settings.getTokenRate(tokens[i]);
            uint value = IERC20(tokens[i]).balanceOf(address(this));
            v = v.add(value.mul(b).div(r));
        }
    }

    function totalAccruedFees() external view returns (uint) {

        return _totalAccruedFees;
    }

    function totalDebt() external view returns (uint) {

        return _totalDebt;
    }

    function getTotalOwners() external view returns (uint) {
        return _totalOwners;
    }

    function getTotalBalance() external view returns (uint) {
        return _totalBalance;
    }

    function ensureCaller(address addr) external view {
        require(callers[addr] == 1, "unauthorized caller");
    }

    function issueCredit(address to, uint value) external {
        
        ensurePrimeCaller();

        require(msg.sender == address(settings));
        issueCreditTokens(to, value);
    }

    function balanceOf(address owner) external view returns (uint) {

        return balances[owner];
    }
    
    function addBalance(address to, address token, uint value) external {

        addBalance(to, token, value, false);
    }

    function transferBalance(address from, address to, uint value) external {
        ensureCaller();
        transferBalanceInternal(from, to, value);
    }
    
    function depositTokens(address to, address token, uint value) external {

        IERC20(token).transferFrom(msg.sender, address(this), value);
        addBalance(to, token, value, true);
        emit DepositTokens(to, token, value);
    }

    function withdrawTokens(address owner, uint value) external {
        
        ensureCaller();
        removeBalance(owner, value);
        burnDebtAndTransferTokens(owner, value);
    }

    function grantTokens(address to, uint value) external {
        
        ensureCaller();
        burnDebtAndTransferTokens(to, value);
    }

    function calcDebt(address addr) public view returns (uint debt) {

        debt = debts[addr];
        if (debt > 0) {
            debt = settings.applyDebtInterestRate(debt, debtsDate[addr]);
        }
    }

    function processIncentivizationPayment(address to, uint credit) external {
        
        ensurePrimeCaller();
        require(to != address(this), "invalid incentivization");

        if (credit > 0) {
            // add debt to credit provier, and increment exchange balance for user
            applyDebtInterestRate(address(this));
            setDebt(address(this), debts[address(this)].add(credit));
            addBalance(to, credit);
            emit AccumulateDebt(to, credit);
        }
    }

    function borrowSellLiquidity(address to, uint credit) external {
        ensureCaller();
        require(settings.checkPoolSellCreditTradable(to) == true, "pool cant buy on credit");
        borrowLiquidity(to, credit);
    }

    function borrowBuyLiquidity(address to, uint credit) external {
        ensureCaller();
        require(settings.checkPoolBuyCreditTradable(to) == true, "pool cant sell on credit");
        borrowLiquidity(to, credit);
    }

    function borrowLiquidity(address to, uint credit) private {
        require(to != address(this), "invalid borrower");
        require(callers[to] == 1, "invalid pool");
        if (credit > 0) {
            // add debt to credit provier, and increment exchange balance for liquidity pool
            applyDebtInterestRate(address(this));
            setDebt(address(this), debts[address(this)].add(credit));
            addBalance(to, credit);
            emit AccumulateDebt(to, credit);
        }
    }

    function processPayment(address from, address to, uint value) external {
        ensureCaller();

        require(from != to);

        if (value > 0) {

            (uint v, uint b) = settings.getProcessingFee();
            if (v > 0) {
                uint fee = MoreMath.min(value.mul(v).div(b), balances[from]);
                value = value.sub(fee);
                emit AccrueFees(from, value);
            }

            uint credit;
            if (balances[from] < value) {
                credit = value.sub(balances[from]);
                value = balances[from];
            }

            transferBalanceInternal(from, to, value);

            if (credit > 0) {                
                applyDebtInterestRate(from);
                setDebt(from, debts[from].add(credit));
                addBalance(to, credit);
                emit AccumulateDebt(to, credit);
            }
        }
    }

    function transferBalanceInternal(address from, address to, uint value) private {
        
        ensureCaller();
        
        removeBalance(from, value);
        addBalance(to, value);
        emit TransferBalance(from, to, value);
    }
    
    function addBalance(address to, address token, uint value, bool trusted) private {

        if (value > 0) {

            if (!trusted) {
                ensureCaller();
            }
            
            (uint r, uint b) = settings.getTokenRate(token);
            require(r != 0 && token != ctAddr, "token not allowed");
            value = value.mul(b).div(r);
            addBalance(to, value);
            emit TransferBalance(address(0), to, value);
        }
    }
    
    function addBalance(address owner, uint value) private {

        if (value > 0) {

            uint burnt = burnDebt(owner, value);
            uint v = value.sub(burnt);

            if (balances[owner] == 0) {
                _totalOwners = _totalOwners.add(1);
            }

            balances[owner] = balances[owner].add(v);
            _totalBalance =_totalBalance.add(v);
        }
    }

    function calcRawCollateralShortage(address owner) public view returns (uint) {
        // this represents the sum of the negative exposure of owner on the exchange from any part of their book where written is greater than holding

        uint bal = balances[owner];
        uint tcoll = IOptionsExchange(exchangeAddr).calcCollateral(owner, false);
        int coll = int(tcoll);
        int net = int(bal) - coll;

        if (net >= 0)
            return 0;

        return uint(net * -1);
    }
    
    function removeBalance(address owner, uint value) private {
        
        require(balances[owner] >= value, "insufficient balance");
        balances[owner] = balances[owner].sub(value);

        if (value > 0) {
            _totalBalance = _totalBalance.sub(value);
        } 

        if (_totalOwners > 0 && balances[owner] == 0) {
            _totalOwners = _totalOwners.sub(1);
        }
    }

    function burnDebtAndTransferTokens(address to, uint value) private {

        if (debts[to] > 0) {
            uint burnt = burnDebt(to, value);
            value = value.sub(burnt);
        }

        transferTokens(to, value);
    }

    function burnDebt(uint value) external returns (uint burnt) {
        ensurePrimeCaller();
        burnt = burnDebt(address(this), value);
    }

    function burnDebt(address from, uint value) private returns (uint burnt) {
        
        uint d = applyDebtInterestRate(from);
        if (d > 0) {
            burnt = MoreMath.min(value, d);
            setDebt(from, d.sub(burnt));
            emit BurnDebt(from, value);
        }
    }

    function applyDebtInterestRate(address owner) private returns (uint debt) {

        uint d = debts[owner];
        if (d > 0) {

            debt = calcDebt(owner);

            if (debt > 0 && debt != d) {
                setDebt(owner, debt);
            }
        }
    }

    function setDebt(address owner, uint value)  private {

        if (debts[owner] >= value) {
            // less debt being set
            _totalDebt = _totalDebt.sub(debts[owner].sub(value));
        } else {
            // more debt being set
            _totalDebt = _totalDebt.add(value.sub(debts[owner]));
        }
        
        debts[owner] = value;
        debtsDate[owner] = settings.exchangeTime();
    }

    function transferTokens(address to, uint value) private {
        
        require(to != address(this) && to != ctAddr, "invalid token transfer address");

        address[] memory tokens = settings.getAllowedTokens();
        for (uint i = 0; i < tokens.length && value > 0; i++) {
            IERC20 t = IERC20(tokens[i]);
            (uint r, uint b) = settings.getTokenRate(tokens[i]);
            if (b != 0) {
                uint v = MoreMath.min(value, t.balanceOf(address(this)).mul(b).div(r));
                t.transfer(to, v.mul(r).div(b));
                emit WithdrawTokens(to, tokens[i], v.mul(r).div(b));
                value = value.sub(v);
            }
        }
        
        if (value > 0) {
            issueCreditTokens(to, value);
        }
    }

    function issueCreditTokens(address to, uint value) private {
        
        (uint r, uint b) = settings.getTokenRate(ctAddr);
        if (b != 0) {
            value = value.mul(r).div(b);
        }
        creditToken.issue(to, value);
        emit WithdrawTokens(to, ctAddr, value);
    }

    function insertPoolCaller(address llp) external {
        ensurePrimeCaller();
        callers[llp] = 1;
    }

    function ensureCaller() private view {        
        require(callers[msg.sender] == 1, "unauthorized caller");
    }

    function ensurePrimeCaller() private view {        
        require(primeCallers[msg.sender] == 1, "unauthorized caller");
    }
}