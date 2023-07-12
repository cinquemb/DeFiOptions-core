pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


interface ITellerInterface {
    enum CommitmentCollateralType {
        NONE, 
        ERC20,
        ERC721,
        ERC1155,
        ERC721_ANY_ID,
        ERC1155_ANY_ID
    }
    struct Commitment {
        uint256 maxPrincipal;
        uint32 expiration;
        uint32 maxDuration;
        uint16 minInterestRate;
        address collateralTokenAddress;
        uint256 collateralTokenId;
        uint256 maxPrincipalPerCollateralAmount;
        CommitmentCollateralType collateralTokenType;
        address lender;
        uint256 marketId;
        address principalTokenAddress;
    }

    function createCommitment(Commitment calldata _commitment, address[] calldata _borrowerAddressList) external returns (uint256 commitmentId_);
    function withdraw(uint256 _bidId) external;
    function acceptCommitment(
        uint256 _commitmentId,
        uint256 _principalAmount,
        uint256 _collateralAmount,
        uint256 _collateralTokenId,//0 for erc20's
        address _collateralTokenAddress,
        uint16 _interestRate, 
        uint32 _loanDuration
    ) external returns (uint256 _bidId);
    function repayLoanFull(uint256 _bidId) external;
}