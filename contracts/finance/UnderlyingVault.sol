pragma solidity >=0.6.0;

import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IERC20Details.sol";
import "../interfaces/IUniswapV2Router01.sol";
import "../interfaces/TimeProvider.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IUnderlyingCreditProvider.sol";
import "../utils/Convert.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeERC20.sol";

contract UnderlyingVault is ManagedContract {

    using SafeERC20 for IERC20_2;
    using SafeMath for uint;
    using SignedSafeMath for int;

    uint private fractionBase = 1e9;

    TimeProvider private time;
    IProtocolSettings private settings;
    ICreditProvider private creditProvider;
    
    mapping(address => uint) private callers;
    mapping(address => mapping(address => uint)) private _totalSupplyRehypothicated;//token-> protocol->amount
    mapping(address => mapping(address => uint)) private _totalSupplyShareRehypothicated;//token share-> protocol->amount
    mapping(address => bool) private _isRehypothicate;
    mapping(address => mapping(address => uint)) private allocation;
    mapping(address => mapping(address => mapping(address => uint))) private _rehypothecationAllocation;//token->protocol->user->amount
    mapping(address => mapping(address => address)) private _activeUserRehypothicationProtocol;//token->user->active protocol

    mapping(address => uint256) _totalSupply;
    //todo, need to modify when creating
    mapping(address => address) _underlyingCreditProvider;

    struct tsVars {
        uint balR;
        uint valR;
        uint rBalR;
    }


    event Lock(address indexed owner, address indexed token, uint value);

    event Liquidate(address indexed owner, address indexed token, uint valueIn, uint valueOut);

    event Release(address indexed owner, address indexed token, uint value);

    function initialize(Deployer deployer) override internal {

        time = TimeProvider(deployer.getContractAddress("TimeProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        
        callers[deployer.getContractAddress("OptionsExchange")] = 1;
        callers[deployer.getContractAddress("CollateralManager")] = 1;
        callers[deployer.getContractAddress("Incentivized")] = 1;
        callers[address(settings)] = 1;
    }


    function setup(Deployer deployer) public {

        time = TimeProvider(deployer.getContractAddress("TimeProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        
        callers[deployer.getContractAddress("OptionsExchange")] = 1;
        callers[deployer.getContractAddress("CollateralManager")] = 1;
        callers[deployer.getContractAddress("Incentivized")] = 1;
        callers[address(settings)] = 1;
    }

    function balanceOf(address owner, address token) public view returns (uint) {

        return allocation[owner][token];
    }

    function totalSupply(address token) public view returns (uint) {
        return _totalSupply[token];
    }

    function getUnderlyingCreditProvider(address token) public view returns (address) {
        return _underlyingCreditProvider[token];
    }

    function setUnderlyingCreditProvider(address token, address udlCreditProviderAddress) external {
        ensureCaller();
        require(udlCreditProviderAddress != address(0), "bad udlcdprov");
        _underlyingCreditProvider[token] = udlCreditProviderAddress;
    }

    function balanceOfRehypothicatedShares(address owner, address token, address rehypothicationManager) public view returns (uint) {
        return _rehypothecationAllocation[token][rehypothicationManager][owner];
    }

    function addUnderlyingShareBalanceRehypothicated(address owner, address token, address rehypothicationManager, uint v) private {
        _rehypothecationAllocation[token][rehypothicationManager][owner] = _rehypothecationAllocation[token][rehypothicationManager][owner].add(v);
        _totalSupplyShareRehypothicated[token][rehypothicationManager] = _totalSupplyShareRehypothicated[token][rehypothicationManager].add(v);
        //TODO: need to add balacne for user
        //IUnderlyingCreditProvider(_underlyingCreditProvider[token]).addBalance();
    }

    function removeUnderlyingSharesBalanceRehypothicated(address owner, address token, address rehypothicationManager, uint v) private {
        _rehypothecationAllocation[token][rehypothicationManager][owner] = _rehypothecationAllocation[token][rehypothicationManager][owner].sub(v);
        _totalSupplyShareRehypothicated[token][rehypothicationManager] = _totalSupplyShareRehypothicated[token][rehypothicationManager].sub(v);
        //TODO: need to remove balacne for user
        //IUnderlyingCreditProvider(_underlyingCreditProvider[token]).removeBalance();
    }

    function totalSupplyRehypothicated(address token, address rehypothicationManager) public view returns (uint) {
        return _totalSupplyRehypothicated[token][rehypothicationManager];
    }

    function addUnderlyingSupplyRehypothicated(address token, address rehypothicationManager, uint value) private {
        _totalSupplyRehypothicated[token][rehypothicationManager] = _totalSupplyRehypothicated[token][rehypothicationManager].add(value);
    }

    function removeUnderlyingSupplyRehypothicated(address token, address rehypothicationManager, uint value) private {
        _totalSupplyRehypothicated[token][rehypothicationManager] = _totalSupplyRehypothicated[token][rehypothicationManager].sub(value);
    }

    function lock(address owner, address token, uint value, bool isRehypothicate, address rehypothicationManager) external {

        ensureCaller();
        
        require(owner != address(0), "invalid owner");
        require(token != address(0), "invalid token");

        allocation[owner][token] = allocation[owner][token].add(value);
        _totalSupply[token] = _totalSupply[token].add(value);

        if (isRehypothicate == true) {
            _isRehypothicate[owner] = true;

            require(settings.isAllowedRehypothicationManager(rehypothicationManager) == true, "rehyM not allowed");

            if (_activeUserRehypothicationProtocol[token][owner] != rehypothicationManager){
                //needs to be null if diff
                require(_activeUserRehypothicationProtocol[token][owner] == address(0), "rehyM already in use");
            } else {
                //is null addr, set
                _activeUserRehypothicationProtocol[token][owner] = rehypothicationManager;
            }

            uint b0 = totalSupplyRehypothicated(token, rehypothicationManager);
            addUnderlyingSupplyRehypothicated(token, rehypothicationManager, value);
            uint b1 = totalSupplyRehypothicated(token, rehypothicationManager);
            uint p = b1.sub(b0).mul(fractionBase).div(b1);
            uint b = 1e3;
            uint v = totalSupplyRehypothicated(token, rehypothicationManager) > 0 ?
                totalSupplyRehypothicated(token, rehypothicationManager).mul(p).mul(b).div(fractionBase.sub(p)) : 
                b1.mul(b);
            v = MoreMath.round(v, b);

            addUnderlyingShareBalanceRehypothicated(owner, token, rehypothicationManager, v);
            
        }

        emit Lock(owner, token, value);
    }

    function liquidate(
        address owner,
        address token,
        address feed,
        uint amountOut
    )
        external
        returns (uint _in, uint _out)
    {
        ensureCaller();
        
        require(owner != address(0), "invalid owner");
        require(token != address(0), "invalid token");
        require(feed != address(0), "invalid feed");


        uint balance = balanceOf(owner, token);

        if (balance > 0) {

            (address _router, address _stablecoin) = settings.getSwapRouterInfo();
            require(
                _router != address(0) && _stablecoin != address(0),
                "invalid swap router settings"
            );

            IUniswapV2Router01 router = IUniswapV2Router01(_router);
            (, int p) = UnderlyingFeed(feed).getLatestPrice();

            address[] memory path = settings.getSwapPath(
                UnderlyingFeed(feed).getUnderlyingAddr(),
                _stablecoin
            );

            (_in, _out) = swapUnderlyingForStablecoin(
                owner,
                router,
                path,
                p,
                balance,
                amountOut
            );
            
            allocation[owner][token] = allocation[owner][token].sub(_in);
            _totalSupply[token] = _totalSupply[token].sub(_in);

            if (_isRehypothicate[owner] == true){
                address rehypothicationManager = _activeUserRehypothicationProtocol[token][owner];

                if (rehypothicationManager != address(0)) {
                    tsVars memory tsv;
                    tsv.balR = balanceOfRehypothicatedShares(owner, token, rehypothicationManager);
                    tsv.valR = valueOfRehypothicatedShares(owner, token, rehypothicationManager);
                    tsv.rBalR = _in.mul(tsv.balR).div(tsv.valR);

                    removeUnderlyingSharesBalanceRehypothicated(owner, token, rehypothicationManager, tsv.rBalR);
                    removeUnderlyingSupplyRehypothicated(token, rehypothicationManager, _in);
                    checkAndResetRehypothicationManager(owner, token, rehypothicationManager);
                }
            }

            emit Liquidate(owner, token, _in, _out);
        }
    }

    function valueOfRehypothicatedShares(address ownr, address token, address rehypothicationManager) public view returns (uint) {
        uint bal = _totalSupplyShareRehypothicated[token][rehypothicationManager];
        uint balOwnr = balanceOfRehypothicatedShares(ownr, token, rehypothicationManager);
        return uint(int(bal))
            .mul(balOwnr).div(_totalSupplyRehypothicated[token][rehypothicationManager]);
    }

    function release(address owner, address token, address feed, uint value) external {
        
        ensureCaller();
        
        require(owner != address(0), "invalid owner");
        require(token != address(0), "invalid token");
        require(feed != address(0), "invalid feed");

        uint bal = allocation[owner][token];
        value = MoreMath.min(bal, value);

        if (bal > 0) {

            allocation[owner][token] = bal.sub(value);
            _totalSupply[token] = _totalSupply[token].sub(value);

            address underlying = UnderlyingFeed(feed).getUnderlyingAddr();


            if (_isRehypothicate[owner] == true){
                address rehypothicationManager = _activeUserRehypothicationProtocol[token][owner];

                if (rehypothicationManager != address(0)) {
                    uint balR = balanceOfRehypothicatedShares(owner, token, rehypothicationManager);
                    value = valueOfRehypothicatedShares(owner, token, rehypothicationManager);
                    removeUnderlyingSharesBalanceRehypothicated(owner, token, rehypothicationManager, balR);
                    removeUnderlyingSupplyRehypothicated(token, rehypothicationManager, value);
                    checkAndResetRehypothicationManager(owner, token, rehypothicationManager);
                }

                //TODO: - issue erc20 collateral credit token for shortfall (when closing covered rehypothicated position) that can be redeemed for underlying
            }

            
            uint v = Convert.from18DecimalsBase(underlying, value);
            IERC20_2(underlying).safeTransfer(owner, v);
            
            emit Release(owner, token, value);
        }
    }

    function checkAndResetRehypothicationManager(address owner, address token, address rehypothicationManager) private {
        uint balR = balanceOfRehypothicatedShares(owner, token, rehypothicationManager);
        if (balR == 0) {
            //unset rehyM
            _activeUserRehypothicationProtocol[token][owner] = address(0);
        }
    }

    function swapUnderlyingForStablecoin(
        address owner,
        IUniswapV2Router01 router,
        address[] memory path,
        int price,
        uint balance,
        uint amountOut
    )
        private
        returns (uint _in, uint _out)
    {
        require(path.length >= 2, "invalid swap path");
        
        (uint r, uint b) = settings.getTokenRate(path[path.length - 1]);

        uint udlBalance = Convert.from18DecimalsBase(path[0], balance);
        
        uint amountInMax = getAmountInMax(
            price,
            amountOut,
            path
        );

        if (amountInMax > udlBalance) {
            amountOut = amountOut.mul(udlBalance).div(amountInMax);
            amountInMax = udlBalance;
        }

        IERC20_2 tk = IERC20_2(path[0]);
        if (tk.allowance(address(this), address(router)) > 0) {
            tk.safeApprove(address(router), 0);
        }
        tk.safeApprove(address(router), amountInMax);

        _out = amountOut;
        _in = router.swapTokensForExactTokens(
            amountOut.mul(r).div(b),
            amountInMax,
            path,
            address(creditProvider),
            time.getNow()
        )[0];
        _in = Convert.to18DecimalsBase(path[0], _in);

        if (amountOut > 0) {
            creditProvider.addBalance(owner, path[path.length - 1], amountOut.mul(r).div(b));
        }
    }

    function getAmountInMax(
        int price,
        uint amountOut,
        address[] memory path
    )
        private
        view
        returns (uint amountInMax)
    {
        uint8 d = IERC20Details(path[0]).decimals();
        amountInMax = amountOut.mul(10 ** uint(d)).div(uint(price));
        
        (uint rTol, uint bTol) = settings.getSwapRouterTolerance();
        amountInMax = amountInMax.mul(rTol).div(bTol);
    }

    function ensureCaller() private view {
        
        require(callers[msg.sender] == 1, "Vault: unauthorized caller");
    }
}