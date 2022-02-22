pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseRehypothecationManager.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/external/aave/ILendingPool.sol";

contract AaveV2MaticRehypothecationManager is BaseRehypothecationManager {
    
    using SafeCast for uint;
    using SafeMath for uint;
    using SignedSafeMath for int;
    uint256 private UINT_MAX = 2**256 - 1;

    function initialize(Deployer deployer) override internal {
        super.initialize(deployer);
    }

    constructor(address counterPartyAddr) public {    
        counterpartyAddress = counterPartyAddr;
    }

    function deposit(address underlying, uint256 amount) virtual internal view returns (uint) {
    	//TODO: MAY NEED TO FIGURE OUT IF THIS WOULD WORK FOR APPROVAL OR NEEDS TO HAPPEN DIFFERENTLY
    	IERC20 tk = IERC20(underlying);
        if (tk.allowance(address(vault), counterpartyAddress) > 0) {
            tk.safeApprove(counterpartyAddress, 0);
        }
        tk.safeApprove(counterpartyAddress, UINT_MAX);
    	ILendingPool(counterpartyAddress).deposit(underlying, uint256 amount, address(vault), 0);
    }

    function withdraw(address underlying, uint256 amount) virtual internal view returns (uint) {
    	ILendingPool(counterpartyAddress).withdraw(underlying, amount, address(vault)) external returns (uint256);
    }
}