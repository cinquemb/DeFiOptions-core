pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "./IOptionsExchange.sol";

interface ICollateralManager {
    function collateralSkew() external view returns (int);
    function calcLiquidationVolume(address owner, IOptionsExchange.OptionData calldata opt, IOptionsExchange.FeedData calldata fd, uint written) external view returns (uint volume);
    function calcLiquidationValue(IOptionsExchange.OptionData calldata opt, uint vol, uint written, uint volume, uint iv) external view returns (uint value);
    function calcCollateral(IOptionsExchange.OptionData calldata opt, uint volume) external view returns (uint);
    function calcIntrinsicValue(IOptionsExchange.OptionData calldata opt) external view returns (int value);
    function calcCollateral(address owner, bool is_regular) external view returns (uint);
    function calcExpectedPayout(address owner) external view returns (int payout) ;
}