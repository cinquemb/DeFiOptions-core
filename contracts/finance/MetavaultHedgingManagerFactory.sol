pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "./MetavaultHedgingManager.sol";

contract MetavaultHedgingManagerFactory is ManagedContract {

    address private readerAddr;
    address private deployerAddress;
    address private positionManagerAddr;
    bytes32 private referralCode;

    constructor(address _positionManager, address _reader, bytes32 _referralCode) public {
        positionManagerAddr = _positionManager;
        readerAddr = _reader;
        referralCode = _referralCode;
    }
    
    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function create(address _poolAddr) external returns (address) {
        address hdgMngr = address(
            new MetavaultHedgingManager(
                deployerAddress,
                positionManagerAddr,
                readerAddr,
                referralCode,
                _poolAddr
            )
        );
        return hdgMngr;
    }
}