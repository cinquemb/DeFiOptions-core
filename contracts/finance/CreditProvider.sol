pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../governance/ProtocolSettings.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ICreditToken.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeERC20.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";


contract CreditProvider is ManagedContract {

    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using SignedSafeMath for int;
    
    ProtocolSettings private settings;
    ICreditToken private creditToken;

    mapping(address => uint) private debts;
    mapping(address => uint) private balances;
    mapping(address => uint) private poolExcessCreditBalance;
    mapping(address => uint) private debtsDate;
    mapping(address => uint) private poolCallers;
    mapping(address => uint) private primeCallers;
    mapping(address => mapping(address => uint)) private optionBorrowedBalance;


    address private exchangeAddr;

    uint private _totalDebt;
    uint private _totalOwners;
    uint private _totalBalance;
    uint private _totalAccruedFees;
    uint private _totalOptionsBorrowed;
    uint private _totalOptionBorrowBalance;


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

        primeCallers[exchangeAddr] = 1;
        primeCallers[address(settings)] = 1;
        primeCallers[address(creditToken)] = 1;
        primeCallers[vaultAddr] = 1;
        primeCallers[collateralManagerAddr] = 1;
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
        ensurePrimeCaller();
        transferBalanceInternal(from, to, value);
    }
    
    function depositTokens(address to, address token, uint value) external {

        IERC20(token).safeTransferFrom(msg.sender, address(this), value);
        addBalance(to, token, value, true);
        emit DepositTokens(to, token, value);
    }

    function withdrawTokens(address owner, uint value) external {
        
        ensurePrimeCaller();
        removeBalance(owner, value);
        burnDebtAndTransferTokens(owner, value);
    }

    function withdrawTokens(address owner, uint value , address[] calldata tokensInOrder, uint[] calldata amountsOutInOrder) external {
        ensurePrimeCaller();
        require(tokensInOrder.length == amountsOutInOrder.length, "token != amounts lists size");
        require(value > 0, "no withdrawl amounts set");
        removeBalance(owner, value);
        burnDebtAndTransferTokensByPreference(owner, value, tokensInOrder, amountsOutInOrder);
    }

    function grantTokens(address to, uint value) external {
        
        ensurePrimeCaller();
        burnDebtAndTransferTokens(to, value);
    }

    function calcDebt(address addr) public view returns (uint debt) {

        debt = debts[addr];
        if (debt > 0) {
            debt = settings.applyDebtInterestRate(debt, debtsDate[addr]);
        }
    }

    function processEarlyLpWithdrawal(address to, uint credit) external {
        
        ensurePoolCaller();
        require(to != address(this), "invalid withrawal request");

        if (credit > 0) {
            // issue credit tokens to withdrawing lp addresss
            issueCreditTokens(to, credit);
        }
    }

    function processIncentivizationPayment(address to, uint credit) external {
        
        ensurePrimeCaller();
        require(to != address(this), "invalid incentivization");
        // increment exchange balance for user
        addBalance(to, credit);
    }

    function borrowBuyLiquidity(address to, uint credit, address option) external {
        ensurePoolCaller();
        require(to != address(this), "invalid borrower");
        require(poolCallers[to] == 1, "invalid pool");
        require(settings.checkPoolBuyCreditTradable(to) == true, "pool cant sell on credit");
        // increment exchange balance for liquidity pool
        addBalance(to, credit);
        //increment value used to write options
        addOptionBorrowBalance(option, to, credit);
    }

    function borrowSellLiquidity(address to, uint credit, address option) external {
        ensurePoolCaller();
        require(to != address(this), "invalid borrower");
        require(poolCallers[to] == 1, "invalid pool");
        require(settings.checkPoolSellCreditTradable(to) == true, "pool cant buy on credit");
        require(
            settings.isAllowedHedgingManager(IGovernableLiquidityPool(to).getHedgingManager()) == true, 
            "pool hedge manager not allowed"
        );

        // increment exchange balance for liquidity pool
        addBalance(to, credit);
        //increment value used to write options
        addOptionBorrowBalance(option, to, credit);
    }

    function processPayment(address from, address to, uint value) external {
        ensurePrimeCaller();

        require(from != to);

        if (value > 0) {

            (uint v, uint b) = settings.getProcessingFee();
            if (v > 0) {
                uint fee = MoreMath.min(value.mul(v).div(b), balances[from]);
                value = value.sub(fee);
                addBalance(address(settings), fee);
                emit AccrueFees(from, fee);
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
        
        ensurePrimeCaller();
        
        removeBalance(from, value);
        addBalance(to, value);
        emit TransferBalance(from, to, value);
    }
    
    function addBalance(address to, address token, uint value, bool trusted) private {

        if (value > 0) {

            if (!trusted) {
                ensurePrimeCaller();
            }
            
            (uint r, uint b) = settings.getTokenRate(token);
            require(r != 0 && token != address(creditToken), "token not allowed");
            value = value.mul(b).div(r);
            addBalance(to, value);
            emit TransferBalance(address(0), to, value);
        }
    }

    function creditPoolBalance(address to, address token, uint value) external {

        require(
            settings.isAllowedHedgingManager(IGovernableLiquidityPool(to).getHedgingManager()) == true, 
            "pool hedge manager not allowed"
        );

        if (value > 0) {

            if (balances[owner] == 0) {
                _totalOwners = _totalOwners.add(1);
            }

            (uint r, uint b) = settings.getTokenRate(token);
            require(r != 0 && token != address(creditToken), "token not allowed");
            value = value.mul(b).div(r);

            balances[owner] = balances[owner].add(value);
            _totalBalance = _totalBalance.add(value);
        }
    }

    funtion debitPoolBalance(address from, address token, uint value) internal {
        ensurePrimeCaller();
        
        require(
            settings.isAllowedHedgingManager(IGovernableLiquidityPool(from).getHedgingManager()) == true, 
            "pool hedge manager not allowed"
        );

        if (balances[from] >= value){
            removeBalance(from, value);

            // try to remove all excess credit
            if (balances[from] >= poolExcessCreditBalance[from]) {
                removeBalance(from, poolExcessCreditBalance[from]);
                poolExcessCreditBalance[from] = 0;
            } else if (poolExcessCreditBalance[from] > 0) {
                // remove some excess credit;
                removeBalance(from, balances[from]);
                poolExcessCreditBalance[from] = poolExcessCreditBalance[from].sub(balances[from]);
            }

        } else {
            // null balance of pool if value > balances[from]
            removeBalance(from, balances[from]);
            // keep track of excess borrowed that hasn't been credited back
            poolExcessCreditBalance[from] = poolExcessCreditBalance[from].add(value.sub(balances[from]));
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
            _totalBalance = _totalBalance.add(v);
        }
    }

    function addOptionBorrowBalance(address option, address pool, uint value) private {
        if (value > 0) {
            if (optionBorrowedBalance[option][pool] == 0) {
                _totalOptionsBorrowed = _totalOptionsBorrowed.add(1);
            }
            optionBorrowedBalance[option][pool] = optionBorrowedBalance[option][pool].add(value);
            _totalOptionBorrowBalance = _totalOptionBorrowBalance.add(value);
        }
    }

    function nullOptionBorrowBalance(address option, address pool) external {
        // is called when options are liquidated and expired otm and have been sold with borrowed liquidity
        // should not revert, should be called by collateral manager
        if ((primeCallers[msg.sender] == 1) && (poolCallers[pool] == 1)) {
            if (optionBorrowedBalance[option][pool] >= 0) {
                if (optionBorrowedBalance[option][pool] > 0) {
                    _totalOptionBorrowBalance = _totalOptionBorrowBalance.sub(optionBorrowedBalance[option][pool]);

                    // remove borrowed balance for pool related to that option
                    if (balances[pool] >= optionBorrowedBalance[option][pool]){
                        removeBalance(pool, optionBorrowedBalance[option][pool]);

                        // try to remove all excess credit
                        if (balances[pool] >= poolExcessCreditBalance[pool]) {
                            removeBalance(pool, poolExcessCreditBalance[pool]);
                            poolExcessCreditBalance[pool] = 0;
                        } else if (poolExcessCreditBalance[pool] > 0) {
                            // remove some excess credit;
                            removeBalance(pool, balances[pool]);
                            poolExcessCreditBalance[pool] = poolExcessCreditBalance[pool].sub(balances[pool]);
                        }

                    } else {
                        // null balance of pool if optionBorrowedBalance[option][pool] > balances[pool]
                        removeBalance(pool, balances[pool]);
                        // keep track of excess borrowed that hasn't been credited back
                        poolExcessCreditBalance[pool] = poolExcessCreditBalance[pool].add(optionBorrowedBalance[option][pool].sub(balances[pool]));
                    }

                    optionBorrowedBalance[option][pool] = 0;
                } 

                if (_totalOptionsBorrowed > 0 && optionBorrowedBalance[option][pool] == 0) {
                    _totalOptionsBorrowed = _totalOptionsBorrowed.sub(1);
                }
            }
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

    function burnDebtAndTransferTokensByPreference(address to, uint value, address[] memory tokensInOrder, uint[] memory amountsOutInOrder) private {

        if (debts[to] > 0) {
            uint burnt = burnDebt(to, value);
            value = value.sub(burnt);
        }

        transferTokensByPreference(to, value, tokensInOrder, amountsOutInOrder);
    }

    function burnDebt(address from, uint value) private returns (uint burnt) {
        
        uint d = applyDebtInterestRate(from);
        if (d > 0) {
            burnt = MoreMath.min(value, d);
            setDebt(from, d.sub(burnt));
            emit BurnDebt(from, burnt);
        }
    }

    function applyDebtInterestRate(address owner) private returns (uint debt) {

        uint d = debts[owner];
        if (d > 0) {

            debt = calcDebt(owner);

            if (debt > 0 && debt != d) {
                setDebt(owner, debt);
                uint diff = debt.sub(d);
                emit AccumulateDebt(owner, diff);
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
        
        require(to != address(this) && to != address(creditToken), "invalid token transfer address");

        address[] memory tokens = settings.getAllowedTokens();
        for (uint i = 0; i < tokens.length && value > 0; i++) {
            IERC20 t = IERC20(tokens[i]);
            (uint r, uint b) = settings.getTokenRate(tokens[i]);
            if (b != 0) {
                uint v = MoreMath.min(value, t.balanceOf(address(this)).mul(b).div(r));
                t.safeTransfer(to, v.mul(r).div(b));
                emit WithdrawTokens(to, tokens[i], v.mul(r).div(b));
                value = value.sub(v);
            }
        }
        
        if (value > 0) {
            issueCreditTokens(to, value);
        }
    }

    function borrowTokensByPreference(address to, uint value, address[] memory tokensInOrder, uint[] memory amountsOutInOrder) external {
        ensurePrimeCaller();
        require(to != address(this) && to != address(creditToken), "invalid token transfer address");

        address[] memory tokens = settings.getAllowedTokens();
       
        // preferred order
        for (uint i = 0; i < tokensInOrder.length && value > 0; i++) {
            if (findAllowedToken(tokensInOrder[i]) && (amountsOutInOrder[i] > 0)) {
                IERC20 t = IERC20(tokensInOrder[i]);
                (uint r, uint b) = settings.getTokenRate(tokensInOrder[i]);
                if (b != 0) {
                    uint v = MoreMath.min(amountsOutInOrder[i], t.balanceOf(address(this)).mul(b).div(r));
                    t.safeTransfer(to, v.mul(r).div(b));
                    emit WithdrawTokens(to, tokensInOrder[i], v.mul(r).div(b));
                    value = value.sub(v);
                    debitPoolBalance(to, tokensInOrder[i], v);
                }
            }

        }
    }

    function transferTokensByPreference(address to, uint value, address[] memory tokensInOrder, uint[] memory amountsOutInOrder) private {
        
        require(to != address(this) && to != address(creditToken), "invalid token transfer address");

        address[] memory tokens = settings.getAllowedTokens();
       
        // preferred order
        for (uint i = 0; i < tokensInOrder.length && value > 0; i++) {
            if (findAllowedToken(tokensInOrder[i]) && (amountsOutInOrder[i] > 0)) {
                IERC20 t = IERC20(tokensInOrder[i]);
                (uint r, uint b) = settings.getTokenRate(tokensInOrder[i]);
                if (b != 0) {
                    uint v = MoreMath.min(amountsOutInOrder[i], t.balanceOf(address(this)).mul(b).div(r));
                    t.safeTransfer(to, v.mul(r).div(b));
                    emit WithdrawTokens(to, tokensInOrder[i], v.mul(r).div(b));
                    value = value.sub(v);
                }
            }

        }

        // default order if lefter over after defined prefs or not enough in defined preferences
        if (value > 0) {
            for (uint i = 0; i < tokens.length && value > 0; i++) {
                IERC20 t = IERC20(tokens[i]);
                (uint r, uint b) = settings.getTokenRate(tokens[i]);
                if (b != 0) {
                    uint v = MoreMath.min(value, t.balanceOf(address(this)).mul(b).div(r));
                    t.safeTransfer(to, v.mul(r).div(b));
                    emit WithdrawTokens(to, tokens[i], v.mul(r).div(b));
                    value = value.sub(v);
                }
            }
        }
        
        if (value > 0) {
            issueCreditTokens(to, value);
        }
    }

    function issueCreditTokens(address to, uint value) private {
        
        (uint r, uint b) = settings.getTokenRate(address(creditToken));
        if (b != 0) {
            value = value.mul(r).div(b);
        }
        creditToken.issue(to, value);
        emit WithdrawTokens(to, address(creditToken), value);
    }

    function insertPoolCaller(address llp) external {
        ensurePrimeCaller();
        poolCallers[llp] = 1;
    }

    function ensureCaller(address addr) external view {
        require(primeCallers[addr] == 1, "unauthorized caller");
    }

    function findAllowedToken(address addr) private view returns (bool){
        address[] memory tokens = settings.getAllowedTokens();

        for (uint i = 0; i < tokens.length; i++) {
            if(addr == tokens[i]) {
                return true;
            }
        }

        return false;
    }

    function ensurePoolCaller() private view {        
        require(poolCallers[msg.sender] == 1, "unauthorized caller");
    }

    function ensurePrimeCaller() private view {        
        require(primeCallers[msg.sender] == 1, "unauthorized caller");
    }
}