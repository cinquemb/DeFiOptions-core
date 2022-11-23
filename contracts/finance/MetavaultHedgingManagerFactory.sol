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

    event NewHedgingManager(
        address indexed hedgingManager,
        address indexed pool
    );

    constructor(address _positionManager, address _reader, bytes32 referralCode) public {
        _positionManagerAddr = _positionManager;
        _readerAddr = _reader;
        _referralCode = referralCode;
    }
    
    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function create(address _poolAddr) external returns (address) {
        /*address hdgMngr = address(
            new MetavaultHedgingManager(
                deployerAddress,
                _poolAddr
            )
        );*/
        address proxyAddr = address(
            new Proxy(
                ManagedContract(deployerAddress).getOwner(),
                address(
                    new MetavaultHedgingManager(
                        deployerAddress,
                        _poolAddr
                    )
                )
            )
        );
        ManagedContract(proxyAddr).initializeAndLock(Deployer(deployerAddress));
        emit NewHedgingManager(proxyAddr, _poolAddr);
        return proxyAddr;
    }
}