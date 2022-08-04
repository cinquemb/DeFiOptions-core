pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface ICreditProvider {
    function addBalance(address to, address token, uint value) external;
    function balanceOf(address owner) external view returns (uint);
    function totalTokenStock() external view returns (uint v);
    function grantTokens(address to, uint value) external;
    function getTotalOwners() external view returns (uint);
    function getTotalBalance() external view returns (uint);
    function processPayment(address from, address to, uint value) external;
    function transferBalance(address from, address to, uint value) external;
    function withdrawTokens(address owner, uint value) external;
    function withdrawTokens(address owner, uint value , address[] calldata tokensInOrder, uint[] calldata amountsOutInOrder) external;
    function insertPoolCaller(address llp) external;
    function processIncentivizationPayment(address to, uint credit) external;
    function borrowBuyLiquidity(address to, uint credit, address option) external;
    function borrowSellLiquidity(address to, uint credit, address option) external;
    function issueCredit(address to, uint value) external;
    function processEarlyLpWithdrawal(address to, uint credit) external;
    function nullOptionBorrowBalance(address option, address pool) external;
    function creditPoolBalance(address to, address token, uint value) external;
    function borrowTokensByPreference(address to, uint value, address[] calldata tokensInOrder, uint[] calldata amountsOutInOrder) external;
    function ensureCaller(address addr) external view;
}