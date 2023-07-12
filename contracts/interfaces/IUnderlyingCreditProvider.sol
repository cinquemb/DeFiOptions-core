pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IUnderlyingCreditProvider {
    function initialize(address _udlCdtk) external;
    function addBalance(address to, address token, uint value) external;
    function addBalance(uint value) external;
    function balanceOf(address owner) external view returns (uint);
    function totalTokenStock() external view returns (uint v);
    function grantTokens(address to, uint value) external;
    function getTotalOwners() external view returns (uint);
    function getTotalBalance() external view returns (uint);
    function processPayment(address from, address to, uint value) external;
    function transferBalance(address from, address to, uint value) external;
    function depositTokens(address to, address token, uint value) external;
    function withdrawTokens(address owner, uint value) external;
    function issueCredit(address to, uint value) external;
    function processEarlyLpWithdrawal(address to, uint credit) external;
    function swapStablecoinForUnderlying(address udlCdtp, address[] calldata path, int price, uint balance, uint amountOut) external;
    function swapBalanceForCreditTokens(address owner, uint value) external;
    function ensureCaller(address addr) external view;
}