pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../deployment/Deployer.sol";
import "../../deployment/ManagedContract.sol";
import "../../interfaces/IProtocolSettings.sol";
import "../../interfaces/IBaseHedgingManager.sol";
import "../../interfaces/ICreditProvider.sol";
import "../../interfaces/IOptionsExchange.sol";
import "../../utils/MoreMath.sol";
import "../../utils/SafeERC20.sol";
import "../../utils/SafeCast.sol";

abstract contract BaseHedgingManager is ManagedContract, IBaseHedgingManager {
	using SafeERC20 for IERC20_2;
    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;

    IProtocolSettings internal settings;
    ICreditProvider internal creditProvider;
    IOptionsExchange internal exchange;

    address public poolAddr;

    function initialize(Deployer deployer) virtual override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
    }

    function getPosSize(address underlying, bool isLong) virtual override public view returns (uint[] memory);
    function getHedgeExposure(address underlying) virtual override public view returns (int256);
    function idealHedgeExposure(address underlying) virtual override public view returns (int256);
    function realHedgeExposure(address udlFeedAddr) virtual override public view returns (int256);
    function balanceExposure(address underlying) virtual override external returns (bool);
    function totalTokenStock() virtual override public view returns (uint v);
    function transferTokensToCreditProvider(address tokenAddr) virtual override external;
}