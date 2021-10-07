pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./IOptionsExchange.sol";

interface IBaseCollateralManager {
    function calcCollateral(IOptionsExchange.OptionData calldata opt, uint volume) external view returns (uint);
    function calcIntrinsicValue(IOptionsExchange.OptionData calldata opt) external view returns (int value);
    function calcCollateral(address owner, bool is_regular) external view returns (uint);
    function calcExpectedPayout(address owner) external view returns (int payout);
    function liquidateExpired(address _tk, address[] calldata owners) external;
    function liquidateOptions(address _tk, address owner) external returns (uint value);
}