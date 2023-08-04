pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../utils/ERC20.sol";
import "../utils/MoreMath.sol";
import "../utils/Decimal.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IUnderlyingCreditProvider.sol";
import "../interfaces/IProposal.sol";


contract UnderlyingCreditToken is ERC20 {

    using SafeMath for uint;
    using Decimal for Decimal.D256;

    IProtocolSettings private settings;
    IUnderlyingCreditProvider private creditProvider;

    mapping(address => uint) private creditDates;

    string private constant _name_prefix = "DeFi Options DAO Credit Token: ";
    string private constant _symbol_prefix = "DODv2-CDTK-";

    string private _name;
    string private _symbol;

    address private issuer;
    address private udlAsset;

    uint private serial;

    constructor(address _deployAddr, address _udlAsset, string memory _nm, string memory _sm) ERC20(string(abi.encodePacked(_name_prefix, _nm))) public {
        //DOMAIN_SEPARATOR = ERC20(address(this)).DOMAIN_SEPARATOR();
        Deployer deployer = Deployer(_deployAddr);

        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        _name = _nm;
        _symbol = _sm;
        udlAsset = _udlAsset;
    }

    function initialize(address underlyingCreditProvider) external {
        require(msg.sender == address(settings), "init not allowed");
        creditProvider = IUnderlyingCreditProvider(underlyingCreditProvider);
        issuer = underlyingCreditProvider;
    }

    function name() override external view returns (string memory) {
        return string(abi.encodePacked(_name_prefix, _name));
    }

    function symbol() override external view returns (string memory) {
        return string(abi.encodePacked(_symbol_prefix, _symbol));
    }

    function getUdlAsset() external view returns (address) {
        return udlAsset;
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
            bal = settings.applyUnderlyingCreditInterestRate(balances[owner], creditDates[owner], udlAsset);
        }
    }

    function requestWithdraw() external {
        uint b = creditProvider.totalTokenStock();
        uint bC = creditProvider.getTotalBalance();

        require(b > 0, "CDTK: please wait to redeem");
        /*
            this is to avoid looping over credit dates and indivual balances, may need to use earliest credit date?
                - may need a linked listed storing credit date reference?
        */
        uint theoreticalMaxBal = settings.applyUnderlyingCreditInterestRate(_totalSupply, creditDates[msg.sender], udlAsset);

        if (b > theoreticalMaxBal) {
            withdrawTokens(msg.sender, balanceOf(msg.sender));
        } else {
            uint diffCreditTime = settings.exchangeTime().sub(creditDates[msg.sender]);
            require(diffCreditTime > settings.getCreditWithdrawlTimeLock() && creditDates[msg.sender] != 0, "CDTK: Must wait until time lock has passed");
            Decimal.D256 memory withdrawalPct = Decimal.ratio(balanceOf(msg.sender), theoreticalMaxBal);
            Decimal.D256 memory udlTokenPct = Decimal.ratio(b, bC);
            uint currWitdrawalLimit = withdrawalPct.mul(udlTokenPct).mul(b).asUint256();
            require(currWitdrawalLimit > 0, "CDTK: please wait to redeem");
            withdrawTokens(msg.sender, currWitdrawalLimit);
        }
    }

    function swapForExchangeBalance(uint value) external {
        creditProvider.addBalance(value);
        removeBalance(msg.sender, value);
        emitTransfer(msg.sender, address(0), value);
    }

    function addBalance(address owner, uint value) override internal {

        updateBalance(owner);
        balances[owner] = balances[owner].add(value);
    }


    function burnBalance(uint value) external {
        updateBalance(msg.sender);
        balances[msg.sender] = balances[msg.sender].sub(value);
    }

    function removeBalance(address owner, uint value) override internal {

        updateBalance(owner);
        balances[owner] = balances[owner].sub(value);
    }

    function updateBalance(address owner) private {

        uint nb = balanceOf(owner);
        uint accrued = nb.sub(balances[owner]);
        _totalSupply = _totalSupply.add(accrued);
        balances[owner] = nb;
        creditDates[owner] = settings.exchangeTime();

        if (accrued > 0) {
            emitTransfer(address(0), owner, accrued);
        }
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
                emitTransfer(owner, address(0), value);
            }
        }
    }
}