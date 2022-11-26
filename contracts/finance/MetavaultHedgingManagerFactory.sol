pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "./MetavaultHedgingManager.sol";

contract MetavaultHedgingManagerFactory is ManagedContract {

    address public readerAddr;
    address public positionManagerAddr;
    bytes32 public referralCode;

    address private deployerAddress;

    event NewHedgingManager(
        address indexed hedgingManager,
        address indexed pool
    );

    constructor(address _positionManager, address _reader, bytes32 rCode) public {
        positionManagerAddr = _positionManager;
        readerAddr = _reader;
        referralCode = rCode;
    }
    
    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function getRemoteContractAddresses() external view returns (address, address, bytes32) {
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("readerAddr()")));
        bytes memory data1 = abi.encodeWithSelector(bytes4(keccak256("positionManagerAddr()")));
        bytes memory data2 = abi.encodeWithSelector(bytes4(keccak256("referralCode()")));
        
        (, bytes memory returnedData) = getImplementation().staticcall(data);
        (, bytes memory returnedData1) = getImplementation().staticcall(data1);
        (, bytes memory returnedData2) = getImplementation().staticcall(data2);

        address pAddr = abi.decode(returnedData1, (address));
        address rAddr = abi.decode(returnedData, (address));
        bytes32 rCode = abi.decode(returnedData2, (bytes32));

        require(pAddr != address(0), "bad pos manager");
        require(rAddr != address(0), "bad reader");

        return (pAddr, rAddr, rCode);
    }

    function create(address _poolAddr) external returns (address) {
        //cant use proxies unless all extenral addrs store here
        require(deployerAddress != address(0), "bad deployer addr");
        address hdgMngr = address(
            new MetavaultHedgingManager(
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