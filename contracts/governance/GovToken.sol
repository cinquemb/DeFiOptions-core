pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";

import "../interfaces/TimeProvider.sol";
import "../utils/ERC20.sol";
import "../utils/Arrays.sol";
import "../utils/SafeMath.sol";
import "./ProposalsManager.sol";
import "./ProtocolSettings.sol";

contract GovToken is ManagedContract, ERC20 {

    using SafeMath for uint;

    ProtocolSettings private settings;
    ProposalsManager private manager;
    
    mapping(address => uint) private transferBlock;
    mapping(address => address) private delegation;
    mapping(address => uint) private delegated;

    string private constant _name = "Governance Token";
    string private constant _symbol = "DODv2";

    event DelegateTo(
        address indexed owner,
        address indexed oldDelegate,
        address indexed newDelegate,
        uint bal
    );

    constructor() ERC20(_name) public {

    }
    
    function initialize(Deployer deployer) override internal {
        DOMAIN_SEPARATOR = ERC20(getImplementation()).DOMAIN_SEPARATOR();
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        manager = ProposalsManager(deployer.getContractAddress("ProposalsManager"));
    }

    function name() override external view returns (string memory) {
        return _name;
    }

    function symbol() override external view returns (string memory) {
        return _symbol;
    }

    function setInitialSupply(address owner, uint supply) public {
        
        require(_totalSupply == 0, "initial supply already set");
        _totalSupply = supply;
        balances[owner] = supply;
        emitTransfer(address(0), owner, supply);
    }


    function delegateBalanceOf(address delegate) external view returns (uint) {

        return delegated[delegate];
    }

    function delegateTo(address newDelegate) public {

        address oldDelegate = delegation[msg.sender];

        require(newDelegate != address(0), "invalid delegate address");

        enforceHotVotingSetting();

        uint bal = balanceOf(msg.sender);


        if (oldDelegate != address(0)) {
            delegated[oldDelegate] = delegated[oldDelegate].sub(bal);
        }

        delegated[newDelegate] = delegated[newDelegate].add(bal);
        delegation[msg.sender] = newDelegate;

        emit DelegateTo(msg.sender, oldDelegate, newDelegate, bal);
    }

    function enforceHotVotingSetting() public view {

        require(
            settings.isHotVotingAllowed() ||
            transferBlock[tx.origin] != block.number,
            "delegation not allowed"
        );
    }

    function calcShare(address owner, uint base) public view returns (uint) {
        return delegated[owner].mul(base).div(settings.getCirculatingSupply());
    }

    function emitTransfer(address from, address to, uint value) override internal {

        transferBlock[tx.origin] = block.number;

        address fromDelegate = delegation[from];
        address toDelegate = delegation[to];

        manager.update(fromDelegate, toDelegate, value);

        if (fromDelegate != address(0)) {
            delegated[fromDelegate] = delegated[fromDelegate].sub(value);
        }

        if (toDelegate != address(0)) {
            delegated[toDelegate] = delegated[toDelegate].add(value);
        }

        emit Transfer(from, to, value);
    }
}