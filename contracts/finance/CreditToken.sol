pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../utils/ERC20.sol";
import "../utils/MoreMath.sol";
import "../utils/Decimal.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IProposal.sol";


contract CreditToken is ManagedContract, ERC20 {

    using SafeMath for uint;
    using Decimal for Decimal.D256;

    IProtocolSettings private settings;
    ICreditProvider private creditProvider;

    mapping(address => uint) private creditDates;

    string private constant _name = "Credit Token";
    string private constant _symbol = "DODv2-CDTK";

    address private issuer;
    address private headAddr;
    address private tailAddr;

    uint private serial;

    constructor() ERC20(_name) public {
        
    }

    function initialize(Deployer deployer) override internal {

        DOMAIN_SEPARATOR = ERC20(getImplementation()).DOMAIN_SEPARATOR();
        
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        issuer = deployer.getContractAddress("CreditIssuer");
    }

    function name() override external view returns (string memory) {
        return _name;
    }

    function symbol() override external view returns (string memory) {
        return _symbol;
    }

    function issue(address to, uint value) public {

        require(msg.sender == issuer, "issuance unallowed");
        addBalance(to, value);
        _totalSupply = _totalSupply.add(value);
        emitTransfer(address(0), to, value);
    }

    function balanceOf(address owner) override public view returns (uint bal) {

        bal = 0;
        if (balances[owner] > 0) {
            bal = settings.applyCreditInterestRate(balances[owner], creditDates[owner]);
        }
    }

    function requestWithdraw() external {
        uint b = creditProvider.totalTokenStock();

        require(b > 0, "CDTK: please wait to redeem");
        /*
            this is to avoid looping over credit dates and indivual balances, may need to use earliest credit date?
                - may need a linked listed storing credit date reference?
        */
        uint theoreticalMaxBal = settings.applyCreditInterestRate(_totalSupply, creditDates[msg.sender]);

        if (b > theoreticalMaxBal) {
            withdrawTokens(msg.sender, balanceOf(msg.sender));
        } else {
            uint diffCreditTime = settings.exchangeTime().sub(creditDates[msg.sender]);
            require(diffCreditTime > settings.getCreditWithdrawlTimeLock() && creditDates[msg.sender] != 0, "CDTK: Must wait until time lock has passed");
            Decimal.D256 memory withdrawalPct = Decimal.ratio(balanceOf(msg.sender), theoreticalMaxBal);
            uint currWitdrawalLimit = withdrawalPct.mul(b).asUint256();
            require(currWitdrawalLimit > 0, "CDTK: please wait to redeem");
            withdrawTokens(msg.sender, currWitdrawalLimit);
        }
    }

    function addBalance(address owner, uint value) override internal {

        updateBalance(owner);
        balances[owner] = balances[owner].add(value);
    }

    function removeBalance(address owner, uint value) override internal {

        updateBalance(owner);
        balances[owner] = balances[owner].sub(value);
    }

    function updateBalance(address owner) private {

        uint nb = balanceOf(owner);
        _totalSupply = _totalSupply.add(nb).sub(balances[owner]);
        balances[owner] = nb;
        creditDates[owner] = settings.exchangeTime();
    }

    function withdrawTokens(address owner, uint value) private returns(uint sent, bool dequeue) {

        if (value > 0) {

            value = MoreMath.min(balanceOf(owner), value);
            uint b = creditProvider.totalTokenStock();

            if (b >= value) {
                sent = value;
                dequeue = true;
            } else {
                sent = b;
            }

            if (sent > 0) {
                removeBalance(owner, sent);
                creditProvider.grantTokens(owner, sent);
            }
        }
    }
}