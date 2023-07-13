pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;
import "../../../interfaces/IERC20_2.sol";


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

    /**
     * @notice Information on the terms of a loan request
     * @param paymentCycleAmount Value of tokens expected to be repaid every payment cycle.
     * @param paymentCycle Duration, in seconds, of how often a payment must be made.
     * @param APR Annual percentage rating to be applied on repayments. (10000 == 100%)
     */
    struct Terms {
        uint256 paymentCycleAmount;
        uint32 paymentCycle;
        uint16 APR;
    }

    /**
     * @notice Details about the loan.
     * @param lendingToken The token address for the loan.
     * @param principal The amount of tokens initially lent out.
     * @param totalRepaid Payment struct that represents the total principal and interest amount repaid.
     * @param timestamp Timestamp, in seconds, of when the bid was submitted by the borrower.
     * @param acceptedTimestamp Timestamp, in seconds, of when the bid was accepted by the lender.
     * @param lastRepaidTimestamp Timestamp, in seconds, of when the last payment was made
     * @param loanDuration The duration of the loan.
     */
    struct LoanDetails {
        IERC20_2 lendingToken;
        uint256 principal;
        //Payment totalRepaid;
        uint32 timestamp;
        uint32 acceptedTimestamp;
        uint32 lastRepaidTimestamp;
        uint32 loanDuration;
    }

    /**
     * @notice Details about a loan request.
     * @param borrower Account address who is requesting a loan.
     * @param receiver Account address who will receive the loan amount.
     * @param lender Account address who accepted and funded the loan request.
     * @param marketplaceId ID of the marketplace the bid was submitted to.
     * @param metadataURI ID of off chain metadata to find additional information of the loan request.
     * @param loanDetails Struct of the specific loan details.
     * @param terms Struct of the loan request terms.
     * @param state Represents the current state of the loan.
     */
    struct Bid {
        address borrower;
        address receiver;
        address lender; // if this is the LenderManager address, we use that .owner() as source of truth
        uint256 marketplaceId;
        bytes32 _metadataURI; // DEPRECATED
        LoanDetails loanDetails;
        Terms terms;
        //BidState state;
        //PaymentType paymentType;
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

    function bids(uint256) external view returns (Bid memory);
}