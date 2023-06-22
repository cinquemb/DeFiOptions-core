pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "truffle/Assert.sol";
//import "truffle/DeployedAddresses.sol";

import "../../../contracts/deployment/Deployer.sol";
import "../../../contracts/finance/CreditProvider.sol";
import "../../../contracts/finance/OptionsExchange.sol";
import "../../../contracts/finance/CollateralManager.sol";
import "../../../contracts/finance/CreditToken.sol";
import "../../../contracts/finance/UnderlyingVault.sol";
import "../../../contracts/finance/Incentivized.sol";
import "../../../contracts/finance/OptionTokenFactory.sol";
import "../../../contracts/finance/PendingExposureRouter.sol";
import "../../../contracts/finance/YieldTracker.sol";

import "../../../contracts/feeds/DEXFeedFactory.sol";
import "../../../contracts/pools/LinearLiquidityPoolFactory.sol";
import "../../../contracts/pools/LinearAnySlopeInterpolator.sol";

import "../../../contracts/finance/UnderlyingCreditProviderFactory.sol";
import "../../../contracts/finance/UnderlyingCreditTokenFactory.sol";
import "../../../contracts/governance/ProtocolSettings.sol";
import "../../../contracts/governance/ProposalsManager.sol";
import "../../../contracts/governance/GovToken.sol";


import "../../../contracts/finance/OptionToken.sol";
import "../../../contracts/interfaces/IOptionsExchange.sol";
import "../../../contracts/interfaces/IGovernableLiquidityPool.sol";
import "../../../contracts/finance/CollateralManager.sol";
import "../../common/actors/PoolTrader.t.sol";
import "../../common/mock/ERC20Mock.t.sol";
import "../../common/mock/EthFeedMock.t.sol";
import "../../common/mock/TimeProviderMock.t.sol";
import "../../common/mock/UniswapV2RouterMock.t.sol";
import "../../common/samples/SimplePoolManagementProposal.t.sol";



contract Base {
    
    int ethInitialPrice = 550e18;
    uint strike = 550e18;
    uint maturity = 30 days;
    
    uint err = 1; // rounding error
    uint cBase = 1e6; // comparison base
    uint volumeBase = 1e18;
    uint timeBase = 1 hours;

    uint spread = 5e7; // 5%
    uint reserveRatio = 20e7; // 20%
    uint withdrawFee = 3e7; // 3%
    uint fractionBase = 1e9;

    EthFeedMock feed;
    ERC20Mock erc20;
    TimeProviderMock time;

    ProtocolSettings settings;
    OptionsExchange exchange;
    CollateralManager collateralManager;

    address pool;
    
    PoolTrader bob;
    PoolTrader alice;
    
    IOptionsExchange.OptionType CALL = IOptionsExchange.OptionType.CALL;
    IOptionsExchange.OptionType PUT = IOptionsExchange.OptionType.PUT;
    
    IGovernableLiquidityPool.Operation NONE = IGovernableLiquidityPool.Operation.NONE;
    IGovernableLiquidityPool.Operation BUY = IGovernableLiquidityPool.Operation.BUY;
    IGovernableLiquidityPool.Operation SELL = IGovernableLiquidityPool.Operation.SELL;

    uint120[] x;
    uint120[] y;
    uint256[3] bsStockSpread;
    string symbol = "ETHM-EC-55e19-2592e3";
    address symbolAddr;

    Deployer deployer;

    //function beforeEachDeploy() public {
    function setUp() public {

        deployer = new Deployer(address(this));
        deployer.setContractAddress("ProtocolSettings", address(new ProtocolSettings(true)));
        deployer.setContractAddress("TimeProvider", address(new TimeProviderMock()));
        deployer.setContractAddress("CreditProvider", address(new CreditProvider()));
        deployer.addAlias("CreditIssuer", "CreditProvider");
        deployer.setContractAddress("CreditToken", address(new CreditToken()));
        deployer.setContractAddress("ProposalsManager", address(new ProposalsManager()));
        deployer.setContractAddress("GovToken", address(new GovToken(address(0))));
        deployer.setContractAddress("CollateralManager", address(new CollateralManager()));
        deployer.setContractAddress("OptionsExchange", address(new OptionsExchange()));
        deployer.setContractAddress("OptionTokenFactory", address(new OptionTokenFactory()));
        deployer.setContractAddress("UnderlyingVault", address(new UnderlyingVault()));
        deployer.setContractAddress("Incentivized", address(new Incentivized()));
        deployer.setContractAddress("UnderlyingCreditProviderFactory", address(new UnderlyingCreditProviderFactory()));
        deployer.setContractAddress("UnderlyingCreditTokenFactory", address(new UnderlyingCreditTokenFactory()));
        deployer.setContractAddress("LinearLiquidityPoolFactory", address(new LinearLiquidityPoolFactory()));
        deployer.setContractAddress("YieldTracker", address(new YieldTracker()));
        deployer.setContractAddress("DEXFeedFactory", address(new DEXFeedFactory()));
        deployer.setContractAddress("Interpolator", address(new LinearAnySlopeInterpolator()));
        deployer.setContractAddress("PendingExposureRouter", address(new PendingExposureRouter()));
        deployer.setContractAddress("UnderlyingToken", address(new ERC20Mock(18)), false);
        deployer.setContractAddress("UnderlyingFeed", address(new EthFeedMock()));
        deployer.setContractAddress("SwapRouter", address(new UniswapV2RouterMock()));
        deployer.setContractAddress("StablecoinA", address(new ERC20Mock(18)), false);
        deployer.setContractAddress("StablecoinB", address(new ERC20Mock(9)), false);
        deployer.setContractAddress("StablecoinC", address(new ERC20Mock(6)), false);
        deployer.deploy(address(this));

        time = TimeProviderMock(deployer.getContractAddress("TimeProvider"));
        feed = EthFeedMock(deployer.getContractAddress("UnderlyingFeed"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = OptionsExchange(deployer.getContractAddress("OptionsExchange"));
        pool = exchange.createPool("DEFAULT", "TEST", false, address(0));
        erc20 = ERC20Mock(deployer.getContractAddress("StablecoinA"));
        collateralManager = CollateralManager(deployer.getContractAddress("CollateralManager"));

        erc20.reset();

        settings.setAllowedToken(address(erc20), 1, 1);
        settings.setUdlFeed(address(feed), 1);

        erc20.issue(address(this), 1000e18);
        erc20.approve(pool, 1000e18);
        IGovernableLiquidityPool(pool).depositTokens(address(this), address(erc20), 1000e18);


        //initialize proposal manager with set parameters propsoal data
        SimplePoolManagementProposal pp = new SimplePoolManagementProposal();
        pp.setExecutionBytes(
            abi.encodeWithSelector(
                bytes4(keccak256("setParameters(uint256,uint256,uint256,uint256,address,uint256)")),
                reserveRatio,
                withdrawFee,
                time.getNow() + 90 days,
                10,
                address(0),
                1000e18
            )
        );
        //registered proposal
        (uint pid, address proposalWrapperAddr) = IProposalManager(
            deployer.getContractAddress("ProposalsManager")
        ).registerProposal(
            address(pp),
            pool,
            IProposalManager.Quorum.QUADRATIC,
            IProposalManager.VoteType.POOL_SETTINGS,
            time.getNow() + 1 hours
        );
        //    function registerProposal(address addr, address poolAddress, Quorum quorum, VoteType voteType, uint expiresAt ) external returns (uint id, address wp);

        
        //vote on proposal
        IProposalWrapper(proposalWrapperAddr).castVote(true);
        //close proposal
        IProposalWrapper(proposalWrapperAddr).close();
        IGovernableLiquidityPool(pool).withdraw(1000e18);

        feed.setPrice(ethInitialPrice);
        time.setFixedTime(0);

        symbolAddr = exchange.createSymbol(address(feed), CALL, strike, maturity);
        symbol = IOptionToken(symbolAddr).symbol();
    }

    function createTraders() public {
        
        bob = createPoolTrader(address(erc20));
        alice = createPoolTrader(address(erc20));
    }

    function depositInPool(address to, uint value) public {
        
        erc20.issue(address(this), value);
        erc20.approve(address(pool), value);
        IGovernableLiquidityPool(pool).depositTokens(to, address(erc20), value);
    }

    function applyBuySpread(uint v) internal view returns (uint) {
        return (v * (spread + fractionBase)) / fractionBase;
    }

    function applySellSpread(uint v) internal view returns (uint) {
        return (v * (fractionBase - spread)) / fractionBase;
    }

    function addSymbol() internal {

        x = [400e18, 450e18, 500e18, 550e18, 600e18, 650e18, 700e18];
        y = [
            30e18,  40e18,  50e18,  50e18, 110e18, 170e18, 230e18,
            25e18,  35e18,  45e18,  45e18, 105e18, 165e18, 225e18
        ];

        bsStockSpread = [
            100 * volumeBase, // buy stock
            200 * volumeBase,  // sell stock
            spread
        ];        

        erc20.issue(address(this), 1000e18);
        erc20.approve(pool, 1000e18);
        IGovernableLiquidityPool(pool).depositTokens(address(this), address(erc20), 1000e18);


        //initialize proposal manager with addSymbol propsoal data
        SimplePoolManagementProposal pp = new SimplePoolManagementProposal();
        pp.setExecutionBytes(
            abi.encodeWithSelector(
                //bytes4(
                //    keccak256("addSymbol(address,uint256,uint256,IOptionsExchange.OptionType,uint256,uint256,uint120[],uint120[],uint256[3])")
                //),
                IGovernableLiquidityPool(pool).addSymbol.selector,
                address(feed),
                strike,
                maturity,
                CALL,
                time.getNow(),
                time.getNow() + 1 days,
                x,
                y,
                bsStockSpread
            )
        );

        //registered proposal
        (uint pid, address proposalWrapperAddr) = IProposalManager(
            deployer.getContractAddress("ProposalsManager")
        ).registerProposal(
            address(pp),
            pool,
            IProposalManager.Quorum.QUADRATIC,
            IProposalManager.VoteType.POOL_SETTINGS,
            time.getNow() + 1 hours
        );        
        //vote on proposal
        IProposalWrapper(proposalWrapperAddr).castVote(true);
        //close proposal
        IProposalWrapper(proposalWrapperAddr).close();
    }

    function calcCollateralUnit() internal view returns (uint) {

        return exchange.calcCollateral(
            address(feed), 
            volumeBase,
            CALL,
            strike,
            maturity
        );
    }

    function createPoolTrader(address stablecoinAddr) internal returns (PoolTrader) {

        return new PoolTrader(stablecoinAddr, address(exchange), address(pool), address(feed), symbol);  
    }
}