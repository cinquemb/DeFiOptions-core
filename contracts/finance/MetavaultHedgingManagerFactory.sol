pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "./MetavaultHedgingManager.sol";

contract MetavaultHedgingManagerFactory is ManagedContract {

    address public _readerAddr;
    address public positionManagerAddr;
    bytes32 public referralCode;

    address private deployerAddress;

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
                _poolAddr
            )
        );
        return hdgMngr;
    }
}