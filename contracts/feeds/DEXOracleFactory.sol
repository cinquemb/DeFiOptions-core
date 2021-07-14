pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../feeds/DEXOracleV1.sol";
import "../feeds/DEXAggregatorV1.sol";

contract DEXOracleFactory is ManagedContract {

    address private exchangeAddr;
    address private deployerAddress;

    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }
    
    /*TODO 
    	need to pass the needed dex information so that different dex can be used, assumes UniswapV2Type
    */

    function create(address underlying, address stable, address dexTokenPair) external returns (address, address) {

    	address oracleAddr = address(new DEXOracleV1(deployerAddress, underlying, stable, dexTokenPair));
    	address aggAddr = address(new DEXAggregatorV1(oracleAddr));
        return (oracleAddr, aggAddr);
    }
}