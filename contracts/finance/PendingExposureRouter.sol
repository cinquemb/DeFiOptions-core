pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IBaseCollateralManager.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/IOptionsExchange.sol";
//import "../interfaces/external/canto/ITurnstile.sol";

//TODO: MANAGED OR NOT? PRIVLEDGED OR NOT?
contract PendingExposureRouter is ManagedContract {
	
	IProtocolSettings private settings;
    ICreditProvider private creditProvider;
    IBaseCollateralManager private collateralManager;
    IOptionsExchange private exchange;

    struct PendingOrder {
        IOptionsExchange.OpenExposureInputs oEi;
        bool[] isApproved;
        uint256 cancelAfter;
    }

    mapping(address => PendingOrder) pendingMarketOrder;

	function initialize(Deployer deployer) override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        collateralManager = IBaseCollateralManager(deployer.getContractAddress("CollateralManager"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));

        /*ITurnstile(0xfA428cA13C63101b537891daE5658785C82b0750).assign(
            ITurnstile(0xfA428cA13C63101b537891daE5658785C82b0750).register(address(settings))
        );*/
    }

    function cancelOrder(address account) external {
        require(msg.sender == account || isPrivledgedPublisherKeeper(account, msg.sender) != address(0), "unauthorized cancel");

        //TODO: cancel order if cancelAfter > current time
        //TODO: SEND BACK PROPER COLLATERAl
        // clear order
        pendingMarketOrder[account] = new PendingOrder();
    };


    function approveOrder(address account, string[] calldata symbols) external {
        address pendingPPk = isPrivledgedPublisherKeeper(account, msg.sender);
        require(pendingPPk != address(0), "unauthorized approval");

        //TODO: cancel order if cancelAfter > current time

        (uint256 maxApprovalsNeeded, uint currentApprovals) = getApprovals(account, symbols);

        // TODO: execute order
        if (currentApprovals == maxApprovalsNeeded){

            /* 
                TODO: CHECK THAT PROPER OPTIONS/CREDITS/COLLATERAL HAS BEEN TRANSFERED 
                    may need to happen in exchange contract to avoid router privledges
            */
        }
        
        // clear order
        pendingMarketOrder[account] = new PendingOrder();
    };

    function createOrder(
        IOptionsExchange.OpenExposureInputs memory oEi,
        uint256 cancelAfter
    ) external {
        //SAVE ORDER
        //CHECK PROPER BALANCES OF ANY COLLATERAL SENT
    };

    function getApprovals(address account, string[] memory symbols) private returns (uint, uint) {
        uint256 maxApprovalsNeeded = pendingMarketOrder[account].oEi.symbols.length;
        uint256 currentApprovals = 0;
        bool[] memory ca = canApprove(account, msg.sender);


        for (uint i=0; i< maxApprovalsNeeded; i++) {
            //check if not already approved, check if can approve, check if symbol in list is approvable
            bool isApprovable = foundSymbol(pendingMarketOrder[account].oEi.symbols[i], symbols);
            if ((pendingMarketOrder[account].isApproved[i] == false) && (ca[i] == true) && isApprovable == true) {
                pendingMarketOrder[account].isApproved[i] = true;
                currentApprovals++;
            } else if (pendingMarketOrder[account].isApproved[i]) {
                currentApprovals++;
            }
        }
        return (maxApprovalsNeeded, currentApprovals);
    }

    function isPrivledgedPublisherKeeper(address account, address caller) private view returns (address) {
        string[] memory symbols = pendingMarketOrder[account].oEi.symbols;
        for (uint i=0; i< symols.length; i++) {
            address optAddr = exchange.resolveToken(symbols[i]);
            IOptionsExchange.OptionData memory optData = getOptionData(optAddr);
            address ppk = UnderlyingFeed(optData.udlFeed).getPrivledgedPublisherKeeper();
            if (ppk == caller) {
                return ppk;
            }
        }

        return address(0);
    }

    function canApprove(address account, address caller) private view returns (bool[] memory) {
        bool[] memory canApprove = bool[](pendingMarketOrder[account].oEi.symbols.length);
        for (uint i=0; i< pendingMarketOrder[account].oEi.symbols.length; i++) {
            address optAddr = exchange.resolveToken(symbols[i]);
            IOptionsExchange.OptionData memory optData = getOptionData(optAddr);
            address ppk = UnderlyingFeed(optData.udlFeed).getPrivledgedPublisherKeeper();
            if (ppk == caller) {
                canApprove[i] = true;
            }
        }

        return canApprove;
    }

    function foundSymbol(string[] memory symbols, string symbol) private pure view returns (bool) {
        for (uint i = 0; i < symbols.length; i++) {
            if (symbols[i] == symbol) {
                return true;
            }
        }

        return false;
    }
}