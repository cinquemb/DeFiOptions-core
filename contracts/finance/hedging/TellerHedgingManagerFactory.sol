pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../deployment/Deployer.sol";
import "../../deployment/ManagedContract.sol";
import "./TellerHedgingManager.sol";

contract TellerHedgingManagerFactory is ManagedContract {

    address public tellerRehypothecationAddr;

    address private deployerAddress;

    event NewHedgingManager(
        address indexed hedgingManager,
        address indexed pool
    );

    constructor(address _tellerRehypothecationAddr) public {
        tellerRehypothecationAddr = _tellerRehypothecationAddr;
    }
    
    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function getRemoteContractAddresses() external view returns (address trAddr) {
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("tellerRehypothecationAddr()")));
        (, bytes memory returnedData) = getImplementation().staticcall(data);
        trAddr = abi.decode(returnedData, (address));

        require(trAddr != address(0), "bad rehypothecation addr");
    }

    function create(address _poolAddr) external returns (address) {
        //cant use proxies unless all extenral addrs store here
        require(deployerAddress != address(0), "bad deployer addr");
        address hdgMngr = address(
            new TellerHedgingManager(
                deployerAddress,
                _poolAddr
            )
        );
        /*
        address proxyAddr = address(
            new Proxy(
                getOwner(),
                hdgMngr
            )
        );
        ManagedContract(proxyAddr).initializeAndLock(Deployer(deployerAddress));*/
        emit NewHedgingManager(hdgMngr, _poolAddr);
        return hdgMngr;
    }
}