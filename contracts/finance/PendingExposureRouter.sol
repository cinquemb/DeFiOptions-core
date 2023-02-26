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

import "../utils/Convert.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeCast.sol";
import "../utils/SafeERC20.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";


contract PendingExposureRouter is ManagedContract {
    
    using SafeCast for uint;
    using SafeERC20 for IERC20_2;
    using SafeMath for uint;
    using SignedSafeMath for int;
	
	IProtocolSettings private settings;
    ICreditProvider private creditProvider;
    IBaseCollateralManager private collateralManager;
    IOptionsExchange private exchange;

    struct PendingOrder {
        IOptionsExchange.OpenExposureInputs oEi;
        bool[] isApproved;
        uint256[] buyPrice;
        uint256 cancelAfter;
    }

    mapping(address => PendingOrder) public pendingMarketOrder;

    function initialize(Deployer deployer) override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        collateralManager = IBaseCollateralManager(deployer.getContractAddress("CollateralManager"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));

        /*
        ITurnstile(0xfA428cA13C63101b537891daE5658785C82b0750).assign(
            ITurnstile(0xfA428cA13C63101b537891daE5658785C82b0750).register(address(settings))
        );
        */
    }

    function cancelOrder(address account) external {
        require(msg.sender == account || isPrivledgedPublisherKeeper(account, msg.sender) != address(0) || (pendingMarketOrder[account].cancelAfter > block.timestamp), "unauthorized cancel");

        for(uint i=0; i<pendingMarketOrder[account].oEi.symbols.length; i++){
            if (pendingMarketOrder[account].oEi.isCovered[i]) {
                //refund proper underlying here
                address optAddr = exchange.resolveToken(pendingMarketOrder[account].oEi.symbols[i]);
                IOptionsExchange.OptionData memory optData = getOptionData(optAddr);
                address underlying = UnderlyingFeed(
                    optData.udlFeed
                ).getUnderlyingAddr();
                IERC20_2(underlying).transfer(
                    account,
                    Convert.from18DecimalsBase(underlying, pendingMarketOrder[account].oEi.volume[i])
                );
            }

            if (pendingMarketOrder[account].oEi.paymentTokens[i] != address(0)) {
                //refund collateral to buy options
                uint256 amountToTransfer = pendingMarketOrder[account].buyPrice[i].mul(pendingMarketOrder[account].oEi.volume[i]).div(exchange.volumeBase());
                IERC20_2(pendingMarketOrder[account].oEi.paymentTokens[i]).transfer(
                    account,
                    Convert.from18DecimalsBase(pendingMarketOrder[account].oEi.paymentTokens[i], amountToTransfer)
                );
            }
        }
        // clear order
        pendingMarketOrder[account] = new PendingOrder();
    };


    function approveOrder(address account, string[] calldata symbols) external {
        address pendingPPk = isPrivledgedPublisherKeeper(account, msg.sender);
        require(pendingPPk != address(0), "unauthorized approval");


        if(pendingMarketOrder[account].cancelAfter > block.timestamp) {
            cancelOrder(account);
        }

        (uint256 maxApprovalsNeeded, uint currentApprovals) = getApprovals(account, symbols);
        if (currentApprovals == maxApprovalsNeeded){
            // handle approvals
            for(uint i=0; i<pendingMarketOrder[account].oEi.symbols.length; i++){
                if (pendingMarketOrder[account].oEi.isCovered[i]) {
                    //try to approve proper underlying here
                    
                    address optAddr = exchange.resolveToken(pendingMarketOrder[account].oEi.symbols[i]);
                    IOptionsExchange.OptionData memory optData = getOptionData(optAddr);
                    address underlying = UnderlyingFeed(
                        optData.udlFeed
                    ).getUnderlyingAddr();

                    IERC20_2(underlying).approve(
                        address(exchange), 
                        Convert.from18DecimalsBase(underlying, pendingMarketOrder[account].oEi.volume[i])
                    );
                }

                if (pendingMarketOrder[account].oEi.paymentTokens[i] != address(0)) {
                    //collateral to approve  buy options
                    uint256 amountToTransfer = pendingMarketOrder[account].buyPrice[i].mul(pendingMarketOrder[account].oEi.volume[i]).div(exchange.volumeBase());
                    IERC20_2(pendingMarketOrder[account].oEi.paymentTokens[i]).approve(
                        address(exchange), 
                        Convert.from18DecimalsBase(pendingMarketOrder[account].oEi.paymentTokens[i], amountToTransfer)
                    );
                }
            }

            //execute order
            exchange.openExposure(
                pendingMarketOrder[account].oEi,
                account
            );
        }
        
        // clear order
        pendingMarketOrder[account] = new PendingOrder();
    };

    function createOrder(
        IOptionsExchange.OpenExposureInputs memory oEi,
        uint256 cancelAfter
    ) external {
        pendingMarketOrder[account] = new PendingOrder();


        require(
            (
                (oEi.symbols.length == oEi.volume.length)  && 
                (oEi.symbols.length == oEi.isShort.length) && 
                (oEi.symbols.length == oEi.isCovered.length) && 
                (oEi.symbols.length == oEi.poolAddrs.length) && 
                (oEi.symbols.length == oEi.paymentTokens.length)
            ),
            "order params dim mismatch"
        );

        for(uint i=0; i<oEi.symbols.length; i++){
            if (oEi.isCovered[i]) {
                //try to transfer proper underlying here
                
                address optAddr = exchange.resolveToken(oEi.symbols[i]);
                IOptionsExchange.OptionData memory optData = getOptionData(optAddr);
                address underlying = UnderlyingFeed(
                    optData.udlFeed
                ).getUnderlyingAddr();
                IERC20_2(underlying).safeTransferFrom(
                    msg.sender,
                    address(this), 
                    Convert.from18DecimalsBase(underlying, oEi.volume[i])
                );
            }

            if (oEi.paymentTokens[i] != address(0)) {
                //collateral to buy options
                (uint256 _price,) = IGovernableLiquidityPool(oEi.poolAddrs[i]).queryBuy(oEi.symbols[i], true);
                uint256 amountToTransfer = _price.mul(oEi.volume[i]).div(exchange.volumeBase());
                IERC20_2(oEi.paymentTokens[i]).safeTransferFrom(
                    msg.sender,
                    address(this), 
                    Convert.from18DecimalsBase(oEi.paymentTokens[i], amountToTransfer)
                );
                pendingMarketOrder[account].buyPrice[i] = _price;
            }
        }

        pendingMarketOrder[account].oEi = oEi;
        pendingMarketOrder[account].cancelAfter = cancelAfter;
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