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
}