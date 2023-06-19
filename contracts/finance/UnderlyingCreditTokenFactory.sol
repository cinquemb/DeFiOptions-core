pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "./UnderlyingCreditToken.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/UnderlyingFeed.sol";

contract UnderlyingCreditTokenFactory is ManagedContract {

    address private deployerAddress;

    event NewUnderlyingCreditToken(
        address indexed hedgingManager,
        address indexed pool
    );
    
    function initialize(Deployer deployer) override internal {
        deployerAddress = address(deployer);
    }

    function create(address _udlFeedAddr) external returns (address) {
        //cant use proxies unless all extenral addrs store here
        require(deployerAddress != address(0), "bad deployer addr");
        address _udlAsset = UnderlyingFeed(_udlFeedAddr).getUnderlyingAddr();
        address hdgMngr = address(
            new UnderlyingCreditToken(
                deployerAddress,
                _udlAsset,
                IERC20Details(_udlAsset).name(),
                IERC20Details(_udlAsset).symbol()
            )
        );
        emit NewUnderlyingCreditToken(hdgMngr, _udlAsset);
        return hdgMngr;
    }
}