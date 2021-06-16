pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../interfaces/IERC20.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeMath.sol";
import "./GovToken.sol";
import "./ProtocolSettings.sol";

abstract contract Proposal {

    using SafeMath for uint;

    enum Quorum { SIMPLE_MAJORITY, TWO_THIRDS, QUADRATIC }

    enum VoteType {PROTOCOL_SETTINGS, POOL_SETTINGS}

    enum Status { PENDING, OPEN, APPROVED, REJECTED }

    GovToken private govToken;
    IERC20 private llpToken;
    ProtocolSettings private settings;

    mapping(address => int) private votes;
    
    uint private id;
    uint private yea;
    uint private nay;
    Quorum private quorum;
    Status private status;
    VoteType private voteType;
    uint private expiresAt;
    bool private closed;

    constructor(
        address _govToken,
        address _settings,
        Quorum _quorum,
        VoteType  _voteType,
        uint _expiresAt
    )
        public
    {
        settings = ProtocolSettings(_settings);
        voteType = _voteType;

        if (voteType == VoteType.PROTOCOL_SETTINGS) {
            govToken = GovToken(_govToken);
            require(_quorum != Quorum.QUADRATIC, "cant be quadratic");
        } else if (voteType == VoteType.POOL_SETTINGS) {
            llpToken = IERC20(_govToken);
            require(_quorum == Quorum.QUADRATIC, "must be quadratic");
            require(_expiresAt > settings.exchangeTime() && _expiresAt.sub(settings.exchangeTime()) > 1 days, "too short expiry");
        } else {
            revert("vote type not specified");
        }
        
        quorum = _quorum;
        status = Status.PENDING;
        expiresAt = _expiresAt;
        closed = false;
    }

    function getId() external view returns (uint) {

        return id;
    }

    function getQuorum() public view returns (Quorum) {

        return quorum;
    }

    function getStatus() public view returns (Status) {

        return status;
    }

    function isExecutionAllowed() private view returns (bool) {

        return status == Status.APPROVED && !closed;
    }

    function isPoolSettingsAllowed() external view returns (bool) {

        return (voteType == VoteType.POOL_SETTINGS) && isExecutionAllowed();
    }

    function isProtocolSettingsAllowed() public view returns (bool) {

        return (voteType == VoteType.PROTOCOL_SETTINGS) && isExecutionAllowed();
    }

    function isClosed() public view returns (bool) {

        return closed;
    }

    function open(uint _id) external {

        if (voteType == VoteType.PROTOCOL_SETTINGS) {
            require(msg.sender == address(govToken)); 
        } else {
            require(msg.sender == address(llpToken)); 
        }
        require(status == Status.PENDING);
        id = _id;
        status = Status.OPEN;
    }

    function castVote(bool support) public {
        
        ensureIsActive();
        require(votes[msg.sender] == 0);
        
        uint balance;

        if (voteType == VoteType.PROTOCOL_SETTINGS) {
            balance = govToken.balanceOf(msg.sender);
        } else {
            balance = llpToken.balanceOf(msg.sender);
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
            if (yea.add(nay) < MoreMath.sqrt(llpToken.totalSupply())) {
                require(expiresAt < settings.exchangeTime());
            }

            if (yea > nay) {
                status = Status.APPROVED;
                executePool(llpToken);
            } else {
                status = Status.REJECTED;
            }
        } else {
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

    function execute(ProtocolSettings _settings) public virtual;

    function executePool(IERC20 _llp) public virtual;

    function ensureIsActive() private view {

        require(!closed);
        require(status == Status.OPEN);
        
        if (voteType == VoteType.PROTOCOL_SETTINGS) {
            require(expiresAt > settings.exchangeTime());
        }      
    }

    function update(address voter, int diff) private {

        if (votes[voter] != 0) {
            ensureIsActive();
            require(msg.sender == address(govToken));

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