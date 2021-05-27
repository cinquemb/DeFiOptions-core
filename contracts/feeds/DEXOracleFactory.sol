pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../feeds/DEXOracleV1.sol";
import "../feeds/DEXAggregatorV1.sol";

contract DEXOracleFactory is ManagedContract {

    address private deployerAddress;

    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }
    /*TODO 
    	need to pass the needed dex information so that different dex can be used
    */


    function create(address tokenPairAddress) external returns (address) {

    	address oracleAddr = address(new DEXOracleV1(tokenPairAddress));
    	address feedAddr = address(new DEXAggregatorV1(oracleAddr));
        return oracleAddr;
    }
}