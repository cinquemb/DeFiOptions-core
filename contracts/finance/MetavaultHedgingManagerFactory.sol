pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "./MetavaultHedgingManager.sol";

contract MetavaultHedgingManagerFactory is ManagedContract {

    address public _readerAddr;
    address public _positionManagerAddr;
    bytes32 public _referralCode;

    address private deployerAddress;

    constructor(address _positionManager, address _reader, bytes32 referralCode) public {
        _positionManagerAddr = _positionManager;
        _readerAddr = _reader;
        _referralCode = referralCode;
    }
    
    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function create(address _poolAddr) external returns (address) {
        address hdgMngr = address(
            new MetavaultHedgingManager(
                deployerAddress,
                _poolAddr
            )
        );
        return hdgMngr;
    }
}