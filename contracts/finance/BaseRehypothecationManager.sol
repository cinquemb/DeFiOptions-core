pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IBaseRehypothecationManager.sol";

abstract contract BaseRehypothecationManager is ManagedContract, IBaseRehypothecationManager {
	using SafeERC20 for IERC20;
    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    IUnderlyingVault private vault;
    IProtocolSettings private settings;
    ICreditProvider private creditProvider;
    IOptionsExchange internal exchange;

    address internal counterpartyAddress;

    function initialize(Deployer deployer) virtual override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
        vault = IUnderlyingVault(deployer.getContractAddress("UnderlyingVault"));
    }

    function deposit(address underlying, uint256 amount) virtual internal view returns (uint);
    function withdraw(address underlying, uint256 amount) virtual internal view returns (uint);

    function borrow(address underlying, uint256 amount) virtual internal view returns (uint);
    function repay(address underlying, uint256 amount) virtual internal view returns (uint);
	
}