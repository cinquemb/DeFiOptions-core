pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../governance/ProtocolSettings.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/ICreditToken.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeERC20.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";


contract UnderlyingCreditProvider {

    using SafeERC20 for IERC20_2;
    using SafeMath for uint;
    using SignedSafeMath for int;
    
    ProtocolSettings private settings;
    ICreditToken private creditToken;

    mapping(address => uint) private debts;
    mapping(address => uint) private balances;
    mapping(address => uint) private debtsDate;
    mapping(address => uint) private primeCallers;

    address private vaultAddr;
    address private exchangeAddr;
    address private udlAssetAddr;

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

    //TODO: needs to come from constructor

    constructor(address _deployAddr, address _udlFeedAddr) public {
        Deployer deployer = Deployer(_deployAddr);
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchangeAddr = deployer.getContractAddress("OptionsExchange");
        vaultAddr = deployer.getContractAddress("UnderlyingVault");
        address collateralManagerAddr = deployer.getContractAddress("CollateralManager");

        udlAssetAddr = UnderlyingFeed(_udlFeedAddr).getUnderlyingAddr();
        primeCallers[exchangeAddr] = 1;
        primeCallers[address(settings)] = 1;
        primeCallers[vaultAddr] = 1;
        primeCallers[collateralManagerAddr] = 1;
    }


    function initialize(address underlyingCreditToken) external {
        ensurePrimeCaller();
        creditToken = ICreditToken(underlyingCreditToken);
        primeCallers[underlyingCreditToken] = 1;
    }

    function totalTokenStock() external view returns (uint v) {
        //TODO: needs to calculate based on vault balance for particular token, minus whats is not available for rehypothocation
        v = IERC20_2(udlAssetAddr).balanceOf(vaultAddr);
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

    function addBalance(uint value) external {
        require(creditToken.balanceOf(msg.sender) >= value, "not enought redeemable debt");
        addBalance(msg.sender, value);
    }

    function transferBalance(address from, address to, uint value) external {
        ensurePrimeCaller();
        transferBalanceInternal(from, to, value);
    }
    
    function depositTokens(address to, address token, uint value) external {
        //TODO: where should this be called from? vault? collateral manager? rehypothication manager?
        IERC20_2(token).safeTransferFrom(msg.sender, address(this), value);
        addBalance(to, token, value, true);
        emit DepositTokens(to, token, value);
    }

    function withdrawTokens(address owner, uint value) external {
        
        ensurePrimeCaller();
        removeBalance(owner, value);
        burnDebtAndTransferTokens(owner, value);
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
        //TODO: limit to underlying token when setup
        require(to != address(this) && to != address(creditToken), "invalid token transfer address");

        address[] memory tokens = settings.getAllowedTokens();
        for (uint i = 0; i < tokens.length && value > 0; i++) {
            IERC20_2 t = IERC20_2(tokens[i]);
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

    function issueCreditTokens(address to, uint value) private {
        
        (uint r, uint b) = settings.getTokenRate(address(creditToken));
        if (b != 0) {
            value = value.mul(r).div(b);
        }
        creditToken.issue(to, value);
        emit WithdrawTokens(to, address(creditToken), value);
    }

    function ensureCaller(address addr) external view {
        require(primeCallers[addr] == 1, "unauthorized caller (ex)");
    }

    function ensurePrimeCaller() private view {        
        require(primeCallers[msg.sender] == 1, "unauthorized caller (prime)");
    }
}