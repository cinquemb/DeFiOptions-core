pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../pools/LinearLiquidityPool.sol";

contract LinearLiquidityPoolFactory is ManagedContract {

    constructor(address deployer) public {

        Deployer(deployer).setContractAddress("LinearLiquidityPoolFactory");
    }

    function initialize(Deployer deployer) override internal {

    }

    function create(string calldata name, string calldata symbolSuffix, address owner, address settings, address creditProvider) external returns (address) {

        return address(new LinearLiquidityPool(name, symbolSuffix, owner, settings, creditProvider, msg.sender));
    }
}