pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IBaseRehypothecationManager.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/IUnderlyingVault.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeERC20.sol";
import "../utils/SafeCast.sol";

abstract contract BaseRehypothecationManager is ManagedContract, IBaseRehypothecationManager {
	using SafeERC20 for IERC20_2;
    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    IProtocolSettings internal settings;
    ICreditProvider internal creditProvider;
    IOptionsExchange internal exchange;
    IUnderlyingVault private vault;

    function initialize(Deployer deployer) virtual override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
        vault = IUnderlyingVault(deployer.getContractAddress("UnderlyingVault"));

    }

    function lend(address asset, address collateral, uint amount) virtual override external;
    function withdraw(address asset, uint amount) virtual override external;
    function borrow(address asset, address collateral, uint amount) virtual override external;
    function repay(address collateral, uint amount) virtual override external;
    function transferTokensToCreditProvider(address tokenAddr) virtual override external;
    function transferTokensToVault(address tokenAddr) virtual override external;
}