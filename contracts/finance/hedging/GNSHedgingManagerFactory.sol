pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../deployment/Deployer.sol";
import "../../deployment/ManagedContract.sol";
import "./GNSHedgingManager.sol";

contract GNSHedgingManagerFactory is ManagedContract {
    address public _daiAddr;
    address public _referrer;
    address public _gnsTradingAddr;
    address public _gnsPairInfoAddr;
    address public _gnsFarmTradingStorageAddr;

    address private deployerAddress;

    constructor(address daiAddr, address referrer, address gnsTradingAddr, address gnsPairInfoAddr, address gnsFarmTradingStorageAddr) public {
        _daiAddr = daiAddr;
        _referrer = referrer; //TODO NOT SURE WHAT TO SET HERE
        _gnsTradingAddr = gnsTradingAddr;
        _gnsPairInfoAddr = gnsPairInfoAddr;
        _gnsFarmTradingStorageAddr = gnsFarmTradingStorageAddr;
    }
    
    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function create(address _poolAddr) external returns (address) {
        address hdgMngr = address(
            new GNSHedgingManager(
                deployerAddress,
                _poolAddr
            )
        );
        return hdgMngr;
    }
}