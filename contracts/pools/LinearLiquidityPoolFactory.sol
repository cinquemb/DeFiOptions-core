pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../pools/GovernableLinearLiquidityPool.sol";

contract LinearLiquidityPoolFactory is ManagedContract {

    address private deployerAddress;

    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function create(string calldata name, string calldata symbolSuffix) external returns (address) {
        GovernableLinearLiquidityPool llp = new GovernableLinearLiquidityPool(name, symbolSuffix, deployerAddress);
        return address(llp);
    }
}