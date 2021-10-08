pragma solidity >=0.6.0;

import "./Proposal.sol";
import "./ProposalsManager.sol";
import "./ProtocolSettings.sol";

import "../interfaces/IERC20.sol";
import "../interfaces/IProtocolSettings.sol";
import "../utils/MoreMath.sol";

contract ProposalWrapper {

    using SafeMath for uint;

    enum Quorum { SIMPLE_MAJORITY, TWO_THIRDS, QUADRATIC }

    enum VoteType {PROTOCOL_SETTINGS, POOL_SETTINGS, ORACLE_SETTINGS}

    enum Status { PENDING, OPEN, APPROVED, REJECTED }

    IERC20 private govToken;
    ProposalsManager private manager;
    IERC20 private llpToken;
    IProtocolSettings private settings;

    mapping(address => int) private votes;

    address public implementation;
    
    uint private id;
    uint private yea;
    uint private nay;
    Quorum private quorum;
    Status private status;
    VoteType private voteType;
    uint private expiresAt;
    bool private closed;
    address private proposer;

    constructor(
        address _implementation,
        address _govToken,
        address _manager,
        address _settings,
        Quorum _quorum,
        VoteType  _voteType,
        uint _expiresAt
    )
        public
    {
        implementation = _implementation;
        manager = ProposalsManager(_manager);
        settings = IProtocolSettings(_settings);
        voteType = _voteType;

        if (voteType == VoteType.PROTOCOL_SETTINGS) {
            govToken = IERC20(_govToken);
            require(_quorum != Quorum.QUADRATIC, "cant be quadratic");
        } else if (voteType == VoteType.POOL_SETTINGS) {
            llpToken = IERC20(_govToken);
            require(_quorum == Quorum.QUADRATIC, "must be quadratic");
            require(_expiresAt > settings.exchangeTime() && _expiresAt.sub(settings.exchangeTime()) > 1 days, "too short expiry");
        }  else if (voteType == VoteType.ORACLE_SETTINGS) {
            govToken = IERC20(_govToken);
            require(_expiresAt > settings.exchangeTime() && _expiresAt.sub(settings.exchangeTime()) > 1 days, "too short expiry");
        } else {
            revert("vote type not specified");
        }
        
        quorum = _quorum;
        status = Status.PENDING;
        expiresAt = _expiresAt;
        closed = false;
        proposer = _govToken;
    }

    function getId() public view returns (uint) {

        return id;
    }

    function getQuorum() public view returns (Quorum) {

        return quorum;
    }

    function getStatus() public view returns (Status) {

        return status;
    }

    function isExecutionAllowed() public view returns (bool) {

        return status == Status.APPROVED && !closed;
    }

    function isPoolSettingsAllowed() external view returns (bool) {

        return (voteType == VoteType.POOL_SETTINGS) && isExecutionAllowed();
    }

    function isProtocolSettingsAllowed() public view returns (bool) {

        return ((voteType == VoteType.PROTOCOL_SETTINGS) || (voteType == VoteType.ORACLE_SETTINGS)) && isExecutionAllowed();
    }

    function isActive() public view returns (bool) {

        if (voteType == VoteType.PROTOCOL_SETTINGS) {
            return
                !closed &&
                status == Status.OPEN &&
                expiresAt > settings.exchangeTime();
        } else {
            return
            !closed &&
            status == Status.OPEN;
        }
    }

    function isClosed() public view returns (bool) {

        return closed;
    }

    function open(uint _id) public {

        require(msg.sender == address(manager), "invalid sender");
        require(status == Status.PENDING, "invalid status");
        id = _id;
        status = Status.OPEN;
    }

    function castVote(bool support) public {
        
        ensureIsActive();
        require(votes[msg.sender] == 0, "already voted");
        
        uint balance;

        if (voteType == VoteType.PROTOCOL_SETTINGS) {
            balance = govToken.delegateBalanceOf(msg.sender);
        } else if (voteType == VoteType.POOL_SETTINGS) {
            balance = llpToken.balanceOf(msg.sender);
        } else {
            balance = govToken.delegateBalanceOf(msg.sender);
        }
        
        require(balance > 0);

        if (support) {
            votes[msg.sender] = int(balance);
            yea = (voteType == VoteType.PROTOCOL_SETTINGS) ? yea.add(balance) : yea.add(MoreMath.sqrt(balance));
        } else {
            votes[msg.sender] = int(-balance);
            nay = (voteType == VoteType.PROTOCOL_SETTINGS) ? nay.add(balance) : nay.add(MoreMath.sqrt(balance));
        }
    }

    function update(address from, address to, uint value) public {

        update(from, -int(value));
        update(to, int(value));
    }

    function close() public {

        ensureIsActive();

        if (quorum == Proposal.Quorum.QUADRATIC) {

            uint256 total;

            if (voteType == VoteType.POOL_SETTINGS) {
                total = llpToken.totalSupply();
            } else {
                total = uint256(settings.getCirculatingSupply());
            }

            if (yea.add(nay) < MoreMath.sqrt(total)) {
                require(expiresAt > settings.exchangeTime(), "not enough votes before expiry");
            }

            if (yea > nay) {
                status = Status.APPROVED;

                if (voteType == VoteType.POOL_SETTINGS) {
                    executePool(llpToken);
                } else {
                    execute(settings);
                }

            } else {
                status = Status.REJECTED;
            }
        } else {

            govToken.enforceHotVotingSetting();

            uint total = settings.getCirculatingSupply();
            
            uint v;
            
            if (quorum == Proposal.Quorum.SIMPLE_MAJORITY) {
                v = total.div(2);
            } else if (quorum == Proposal.Quorum.TWO_THIRDS) {
                v = total.mul(2).div(3);
            } else {
                revert();
            }

            if (yea > v) {
                status = Status.APPROVED;
                execute(settings);
            } else if (nay >= v) {
                status = Status.REJECTED;
            } else {
                revert("quorum not reached");
            }

        }        

        closed = true;
    }

    function ensureIsActive() private view {

        require(isActive(), "ProposalWrapper not active");
    }

    function update(address voter, int diff) private {

        if (votes[voter] != 0 && isActive()) {
            require(msg.sender == address(manager), "invalid sender");

            uint _diff = MoreMath.abs(diff);
            uint oldBalance = MoreMath.abs(votes[voter]);
            uint newBalance = diff > 0 ? oldBalance.add(_diff) : oldBalance.sub(_diff);

            if (votes[voter] > 0) {
                yea = (voteType == VoteType.PROTOCOL_SETTINGS) ? yea.add(
                    newBalance
                ).sub(oldBalance) : yea.add(
                    MoreMath.sqrt(newBalance)
                ).sub(MoreMath.sqrt(oldBalance));
            } else {
                nay = (voteType == VoteType.PROTOCOL_SETTINGS) ? nay.add(
                    newBalance
                ).sub(oldBalance) : nay.add(
                    MoreMath.sqrt(newBalance)
                ).sub(MoreMath.sqrt(oldBalance));
            }
        }
    }
}