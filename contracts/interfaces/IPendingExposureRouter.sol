pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./IOptionsExchange.sol";

interface IPendingExposureRouter {
    function getMaxPendingMarketOrders() external view returns (uint256);
    function cancelOrder(uint256 orderId) external;
    function approveOrder(uint256 orderId, string[] calldata symbols) external;
    function createOrder(IOptionsExchange.OpenExposureInputs calldata oEi, uint256 cancelAfter) external;
}