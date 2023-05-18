pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
//import "../deployment/ManagedContract.sol";
import "./D8xHedgingManager.sol";

//contract D8xHedgingManagerFactory is ManagedContract {
contract D8xHedgingManagerFactory {

    address public orderBookAddr;
    address public perpetualProxy;

    address private deployerAddress;

    event NewHedgingManager(
        address indexed hedgingManager,
        address indexed pool
    );

    constructor(address _orderBookAddr, address _perpetualProxy) public {
        orderBookAddr = _orderBookAddr;
        perpetualProxy = _perpetualProxy;
        deployerAddress = address(0x12062A38E2af0fFD760927955e907D64959d0B14);
    }
    
    //function initialize(Deployer deployer) override internal {
    function initialize(Deployer deployer) internal {
        deployerAddress = address(deployer);
    }

    function getRemoteContractAddresses() external view returns (address, address) {
        /*
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("orderBookAddr()")));
        bytes memory data1 = abi.encodeWithSelector(bytes4(keccak256("perpetualProxy()")));
        
        (, bytes memory returnedData) = getImplementation().staticcall(data);
        (, bytes memory returnedData1) = getImplementation().staticcall(data1);

        address obAddr = abi.decode(returnedData, (address));
        address ppAddr = abi.decode(returnedData1, (address));

        require(obAddr != address(0), "bad order book");
        require(ppAddr != address(0), "bad perp proxy");

        return (obAddr, ppAddr);
        */
        return (orderBookAddr, perpetualProxy);
    }

    function create(address _poolAddr) external returns (address) {
        //cant use proxies unless all extenral addrs store here
        require(deployerAddress != address(0), "bad deployer addr");
        address hdgMngr = address(
            new D8xHedgingManager(
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