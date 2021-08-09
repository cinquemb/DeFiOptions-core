pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface ICreditProvider {
    function addBalance(address to, address token, uint value) external;
    function balanceOf(address owner) external view returns (uint);
    function totalTokenStock() external view returns (uint v);
    function grantTokens(address to, uint value) external;
    function getTotalOwners() external view returns (uint);
    function getTotalBalance() external view returns (uint);
    function ensureCaller(address addr) external view;
    function processPayment(address from, address to, uint value) external;
    function transferBalance(address from, address to, uint value) external;
    function withdrawTokens(address owner, uint value) external;
    function insertPoolCaller(address llp) external;
    function processIncentivizationPayment(address to, uint credit) external;
    function borrowBuyLiquidity(address to, uint credit) external;
    function issueCredit(address to, uint value) external;
    function processEarlyLpWithdrawal(address to, uint credit) external;
    function burnDebt(uint value) external returns (uint burnt);
}