pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/IGovernableLiquidityPool.sol";

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
    IOptionsExchange private exchange;

    struct PendingOrder {
        bool canceled;
        address account;
        bool[] isApproved;
        uint256[] buyPrice;
        uint256 cancelAfter;
        IOptionsExchange.OpenExposureInputs oEi;
    }

    PendingOrder[] private pendingMarketOrders;

    function initialize(Deployer deployer) override internal {
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));

        /*
        ITurnstile(0xfA428cA13C63101b537891daE5658785C82b0750).assign(
            ITurnstile(0xfA428cA13C63101b537891daE5658785C82b0750).register(address(settings))
        );
        */
    }

    function getMaxPendingMarketOrders() public view returns (uint256) {
        if (pendingMarketOrders.length == 0) {
            return 0;
        } else {
            return pendingMarketOrders.length.sub(1);
        }
    }

    function cancelOrder(uint256 orderId) public {
        require(
            (msg.sender == pendingMarketOrders[orderId].account) || (isPrivledgedPublisherKeeper(orderId, msg.sender) != address(0)) || (pendingMarketOrders[orderId].cancelAfter > block.timestamp),
            "unauthorized cancel"
        );

        for(uint i=0; i<pendingMarketOrders[orderId].oEi.symbols.length; i++){
            if (pendingMarketOrders[orderId].oEi.isCovered[i]) {
                //refund proper underlying here
                address optAddr = exchange.resolveToken(pendingMarketOrders[orderId].oEi.symbols[i]);
                IOptionsExchange.OptionData memory optData = exchange.getOptionData(optAddr);
                address underlying = UnderlyingFeed(
                    optData.udlFeed
                ).getUnderlyingAddr();
                IERC20_2(underlying).transfer(
                    pendingMarketOrders[orderId].account,
                    Convert.from18DecimalsBase(underlying, pendingMarketOrders[orderId].oEi.volume[i])
                );
            }

            if (pendingMarketOrders[orderId].oEi.paymentTokens[i] != address(0)) {
                //refund collateral to buy options
                uint256 amountToTransfer = pendingMarketOrders[orderId].buyPrice[i].mul(pendingMarketOrders[orderId].oEi.volume[i]).div(exchange.volumeBase());
                IERC20_2(pendingMarketOrders[orderId].oEi.paymentTokens[i]).transfer(
                    pendingMarketOrders[orderId].account,
                    Convert.from18DecimalsBase(pendingMarketOrders[orderId].oEi.paymentTokens[i], amountToTransfer)
                );
            }
        }
        // clear order
        pendingMarketOrders[orderId].canceled = true;
    }

    //TODO: "InternalCompilerError: I sense a disturbance in the stack: 6 vs 7"
    function approveOrder(uint256 orderId, string[] calldata symbols) external {
        address pendingPPk = isPrivledgedPublisherKeeper(orderId, msg.sender);
        require(pendingPPk != address(0), "unauthorized approval");


        if(pendingMarketOrders[orderId].cancelAfter > block.timestamp) {
            cancelOrder(orderId);
        }

        (uint256 maxApprovalsNeeded, uint currentApprovals) = getApprovals(orderId, symbols);
        if (currentApprovals == maxApprovalsNeeded){
            // handle approvals
            for(uint i=0; i<pendingMarketOrders[orderId].oEi.symbols.length; i++){
                if (pendingMarketOrders[orderId].oEi.isCovered[i]) {
                    //try to approve proper underlying here
                    
                    address optAddr = exchange.resolveToken(pendingMarketOrders[orderId].oEi.symbols[i]);
                    IOptionsExchange.OptionData memory optData = exchange.getOptionData(optAddr);
                    address underlying = UnderlyingFeed(
                        optData.udlFeed
                    ).getUnderlyingAddr();

                    IERC20_2(underlying).approve(
                        address(exchange), 
                        Convert.from18DecimalsBase(underlying, pendingMarketOrders[orderId].oEi.volume[i])
                    );
                }

                if (pendingMarketOrders[orderId].oEi.paymentTokens[i] != address(0)) {
                    //collateral to approve  buy options
                    uint256 amountToTransfer = pendingMarketOrders[orderId].buyPrice[i].mul(pendingMarketOrders[orderId].oEi.volume[i]).div(exchange.volumeBase());
                    IERC20_2(pendingMarketOrders[orderId].oEi.paymentTokens[i]).approve(
                        address(exchange), 
                        Convert.from18DecimalsBase(pendingMarketOrders[orderId].oEi.paymentTokens[i], amountToTransfer)
                    );
                }
            }

            //execute order
            exchange.openExposure(
                pendingMarketOrders[orderId].oEi,
                pendingMarketOrders[orderId].account
            );
        }
        
        // clear order
        pendingMarketOrders[orderId].canceled = true;
    }

    function createOrder(
        IOptionsExchange.OpenExposureInputs memory oEi,
        uint256 cancelAfter
    ) public {
        pendingMarketOrders.push();
        uint256 orderId = getMaxPendingMarketOrders();

        require(
            (oEi.symbols.length == oEi.volume.length)  && (oEi.symbols.length == oEi.isShort.length) && (oEi.symbols.length == oEi.isCovered.length) && (oEi.symbols.length == oEi.poolAddrs.length) && (oEi.symbols.length == oEi.paymentTokens.length),
            "order params dim mismatch"
        );

        pendingMarketOrders[orderId].isApproved = new bool[](oEi.symbols.length);
        pendingMarketOrders[orderId].buyPrice = new uint256[](oEi.symbols.length);

        for(uint i=0; i<oEi.symbols.length; i++){
            pendingMarketOrders[orderId].isApproved[i] = false;
            pendingMarketOrders[orderId].buyPrice[i] = 0;
            if (oEi.isCovered[i]) {
                //try to transfer proper underlying here
                
                address optAddr = exchange.resolveToken(oEi.symbols[i]);
                IOptionsExchange.OptionData memory optData = exchange.getOptionData(optAddr);
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
                pendingMarketOrders[orderId].buyPrice[i] = _price;
            }
        }

        pendingMarketOrders[orderId].account = msg.sender;
        pendingMarketOrders[orderId].oEi = oEi;
        pendingMarketOrders[orderId].cancelAfter = cancelAfter;
        pendingMarketOrders[orderId].canceled = false;
    }

    function getApprovals(uint256 orderId, string[] memory symbols) internal returns (uint, uint) {
        uint256 maxApprovalsNeeded = pendingMarketOrders[orderId].oEi.symbols.length;
        uint256 currentApprovals = 0;
        bool[] memory ca = canApprove(orderId, msg.sender);


        for (uint i=0; i< maxApprovalsNeeded; i++) {
            //check if not already approved, check if can approve, check if symbol in list is approvable
            bool isApprovable = foundSymbol(pendingMarketOrders[orderId].oEi.symbols[i], symbols);
            if ((pendingMarketOrders[orderId].isApproved[i] == false) && (ca[i] == true) && isApprovable == true) {
                pendingMarketOrders[orderId].isApproved[i] = true;
                currentApprovals++;
            } else if (pendingMarketOrders[orderId].isApproved[i]) {
                currentApprovals++;
            }
        }
        return (maxApprovalsNeeded, currentApprovals);
    }

    function isPrivledgedPublisherKeeper(uint256 orderId, address caller) internal view returns (address) {
        for (uint i=0; i< pendingMarketOrders[orderId].oEi.symbols.length; i++) {
            address optAddr = exchange.resolveToken(pendingMarketOrders[orderId].oEi.symbols[i]);
            IOptionsExchange.OptionData memory optData = exchange.getOptionData(optAddr);
            address ppk = UnderlyingFeed(optData.udlFeed).getPrivledgedPublisherKeeper();
            if (ppk == caller) {
                return ppk;
            }
        }

        return address(0);
    }

    function canApprove(uint256 orderId, address caller) internal view returns (bool[] memory) {
        bool[] memory canApprove = new bool[](pendingMarketOrders[orderId].oEi.symbols.length);
        for (uint i=0; i< pendingMarketOrders[orderId].oEi.symbols.length; i++) {
            address optAddr = exchange.resolveToken(pendingMarketOrders[orderId].oEi.symbols[i]);
            IOptionsExchange.OptionData memory optData = exchange.getOptionData(optAddr);
            address ppk = UnderlyingFeed(optData.udlFeed).getPrivledgedPublisherKeeper();
            if (ppk == caller) {
                canApprove[i] = true;
            }
        }

        return canApprove;
    }

    function foundSymbol(string memory symbol, string[] memory symbols) private pure returns (bool) {
        for (uint i = 0; i < symbols.length; i++) {
            if (strcmp(symbols[i], symbol) == true) {
                return true;
            }
        }

        return false;
    }

    function memcmp(bytes memory a, bytes memory b) private pure returns(bool){
        return (a.length == b.length) && (keccak256(a) == keccak256(b));
    }
    function strcmp(string memory a, string memory b) private pure returns(bool){
        return memcmp(bytes(a), bytes(b));
    }
}