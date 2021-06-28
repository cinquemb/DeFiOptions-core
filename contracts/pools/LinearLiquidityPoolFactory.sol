pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../pools/LinearLiquidityPool.sol";

contract LinearLiquidityPoolFactory is ManagedContract {

    address private deployerAddress;

    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function create(string calldata name, string calldata symbolSuffix, address owner) external returns (address) {
        LinearLiquidityPool llp = new LinearLiquidityPool(name, symbolSuffix, owner, deployerAddress);
        return address(llp);
    }
}