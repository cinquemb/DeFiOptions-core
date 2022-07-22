pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IBaseHedgingManager.sol";

abstract contract BaseHedgingManager is ManagedContract, IBaseHedgingManager {
	using SafeERC20 for IERC20;
    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    IProtocolSettings private settings;
    ICreditProvider private creditProvider;
    IOptionsExchange internal exchange;

    function initialize(Deployer deployer) virtual override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
    }

    function getHedgeExposure(address underlying) virtual internal view returns (uint);
    function idealHedgeExposure(address underlying) virtual internal view returns (uint);
    function realHedgeExposure(address underlying) virtual internal view returns (uint);
    function balanceExposure(address underlying) virtual internal returns (bool); //TODO: CAN ONLY DO THIS EVERY 15 MIN WITH METAVAULT
}