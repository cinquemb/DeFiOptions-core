pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IVault {
    function allWhitelistedTokensLength() external view returns (uint256);
    function allWhitelistedTokens(uint256) external view returns (address);
}
