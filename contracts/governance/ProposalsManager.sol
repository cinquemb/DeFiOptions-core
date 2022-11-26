pragma solidity >=0.6.0;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../utils/Arrays.sol";
import "../utils/SafeMath.sol";
import "./ProposalWrapper.sol";
import "./GovToken.sol";

contract ProposalsManager is ManagedContract {

    using SafeMath for uint;

    IProtocolSettings private settings;
    GovToken private govToken;

    mapping(address => uint) private proposingDate;
    mapping(address => address) private wrapper;
    mapping(uint => address) private idProposalMap;
    
    uint private serial;
    address[] private proposals;

    event RegisterProposal(
        address indexed wrapper,
        address indexed addr,
        ProposalWrapper.Quorum quorum,
        uint expiresAt
    );
    
    function initialize(Deployer deployer) override internal {

        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        govToken = GovToken(deployer.getContractAddress("GovToken"));
        serial = 1;
    }

    function registerProposal(
        address addr,
        address poolAddress,
        ProposalWrapper.Quorum quorum,
        ProposalWrapper.VoteType voteType,
        uint expiresAt
    )
        public
        returns (uint id, address wp)
    {    
        
        (uint v, uint b) = settings.getMinShareForProposal();
        address governanceToken;
        
        if ((voteType == ProposalWrapper.VoteType.PROTOCOL_SETTINGS) || (voteType == ProposalWrapper.VoteType.ORACLE_SETTINGS)) {
            require(
                proposingDate[msg.sender] == 0 || settings.exchangeTime().sub(proposingDate[msg.sender]) > 1 days,
                "minimum interval between proposals not met"
            );
            require(govToken.calcShare(msg.sender, b) >= v, "insufficient share");
            governanceToken = address(govToken);
            proposingDate[msg.sender] = settings.exchangeTime();
        } else {
            governanceToken = poolAddress;
        }

        ProposalWrapper w = new ProposalWrapper(
            addr,
            governanceToken,
            address(this),
            address(settings),
            quorum,
            voteType,
            expiresAt
        );

        id = serial++;
        w.open(id);
        wp = address(w);
        proposals.push(wp);
        wrapper[addr] = wp;
        idProposalMap[id] = addr;

        emit RegisterProposal(wp, addr, quorum, expiresAt);
    }

    function isRegisteredProposal(address addr) public view returns (bool) {
        
        address wp = wrapper[addr];
        if (wp == address(0)) {
            return false;
        }
        
        ProposalWrapper w = ProposalWrapper(wp);
        return w.implementation() == addr;
    }

    function proposalCount() public view returns (uint) {
        return serial;
    }

    function resolveProposal(uint id) public view returns (address) {

        return idProposalMap[id];
    }

    function resolve(address addr) public view returns (address) {

        return wrapper[addr];
    }

    function update(address from, address to, uint value) public {

        require(msg.sender == address(govToken), "invalid sender");

        for (uint i = 0; i < proposals.length; i++) {
            ProposalWrapper w = ProposalWrapper(proposals[i]);
            if (!w.isActive()) {
                Arrays.removeAtIndex(proposals, i);
                i--;
            } else {
                w.update(from, to, value);
            }
        }
    }
}