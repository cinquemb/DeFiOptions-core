pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../deployment/Deployer.sol";
import "../../deployment/ManagedContract.sol";
import "./UnderlyingCreditProvider.sol";

contract UnderlyingCreditProviderFactory is ManagedContract {

    address private deployerAddress;

    event NewUnderlyingCreditProvider(
        address indexed udlcdtp,
        address indexed udlfeed
    );

    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function create(address _udlFeedAddr) external returns (address) {
        //cant use proxies unless all extenral addrs store here
        require(deployerAddress != address(0), "bad deployer addr");
        address udlcdtp = address(
            new UnderlyingCreditProvider(
                deployerAddress,
                _udlFeedAddr
            )
        );
        emit NewUnderlyingCreditProvider(udlcdtp, _udlFeedAddr);
        return udlcdtp;
    }
}