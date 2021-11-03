pragma solidity >=0.6.0;

import "../../../contracts/governance/Proposal.sol";

contract ChangeInterestRateProposal is Proposal {

    uint interestRate;
    uint interestRateBase;


    constructor(
        address _implementation,
        address _govToken,
        address _manager,
        address _settings,
        Proposal.Quorum _quorum,
        Proposal.VoteType  _voteType,
        uint expiresAt
    ) public Proposal(_implementation, _govToken, _manager, _settings, _quorum, _voteType, expiresAt)
    
    function setInterestRate(uint ir, uint b) public {

        require(ir > 0);
        require(interestRate == 0);

        interestRate = ir;
        interestRateBase = b;
    }

    function getName() public override view returns (string memory) {

        return "Change Debt Interest Rate";
    }

    function execute(IProtocolSettings settings) public override {
        
        require(interestRate > 0, "interest rate value not set");
        settings.setDebtInterestRate(interestRate, interestRateBase);
    }
}