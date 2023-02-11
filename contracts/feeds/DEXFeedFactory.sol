pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../feeds/DEXOracleV1.sol";
import "../feeds/DEXAggregatorV1.sol";
import "../feeds/DEXFeed.sol";
import "../interfaces/IERC20Details.sol";

contract DEXFeedFactory is ManagedContract {

    address private exchangeAddr;
    address private deployerAddress;
    address private timeProviderAddress;

    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
        timeProviderAddress = deployer.getContractAddress("TimeProvider");
    }
    
    /*
    	Assumes like dexTokenPair is of Uniswap V2 like 
    */

    function create(address underlying, address stable, address dexTokenPair) external returns (address) {
    	address oracleAddr = address(new DEXOracleV1(deployerAddress, underlying, stable, dexTokenPair));
    	address aggAddr = address(new DEXAggregatorV1(oracleAddr));
        string memory dexUdlSymbol = IERC20Details(underlying).symbol();
        string memory feedName = string(abi.encodePacked(dexUdlSymbol, "/", "USD", "-", dexTokenPair));
        uint[] memory times;
        int[] memory prices;
        address feedAddr = address(
            new DEXFeed(
                feedName,
                underlying,
                aggAddr,
                timeProviderAddress,
                0,
                times,
                prices
            )
        );
        return feedAddr;
    }
}