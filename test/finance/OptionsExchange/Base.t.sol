pragma solidity >=0.6.0;

import "truffle/Assert.sol";

//import "truffle/DeployedAddresses.sol";

import "../../../contracts/deployment/Deployer.sol";
import "../../../contracts/finance/credit/CreditProvider.sol";
import "../../../contracts/finance/OptionsExchange.sol";
import "../../../contracts/finance/collateral/CollateralManager.sol";
import "../../../contracts/finance/credit/CreditToken.sol";
import "../../../contracts/finance/UnderlyingVault.sol";
import "../../../contracts/finance/Incentivized.sol";
import "../../../contracts/finance/OptionTokenFactory.sol";
import "../../../contracts/finance/PendingExposureRouter.sol";
import "../../../contracts/finance/YieldTracker.sol";

import "../../../contracts/feeds/DEXFeedFactory.sol";
import "../../../contracts/pools/LinearLiquidityPoolFactory.sol";
import "../../../contracts/pools/LinearAnySlopeInterpolator.sol";

import "../../../contracts/finance/credit/UnderlyingCreditProviderFactory.sol";
import "../../../contracts/finance/credit/UnderlyingCreditTokenFactory.sol";
import "../../../contracts/governance/ProtocolSettings.sol";
import "../../../contracts/governance/ProposalsManager.sol";
import "../../../contracts/governance/GovToken.sol";

import "../../../contracts/finance/OptionToken.sol";
import "../../../contracts/interfaces/IOptionsExchange.sol";

import "../../common/actors/OptionsTrader.t.sol";
import "../../common/mock/ERC20Mock.t.sol";
import "../../common/mock/EthFeedMock.t.sol";
import "../../common/mock/TimeProviderMock.t.sol";
import "../../common/mock/UniswapV2RouterMock.t.sol";
import "../../common/samples/SimplePoolManagementProposal.t.sol";

contract Base {
    
    int ethInitialPrice = 550e18;
    uint lowerVol;
    uint upperVol;
    
    uint err = 1; // rounding error
    uint cBase = 1e8; // comparison base
    uint volumeBase = 1e18;
    uint timeBase = 1 hours;
    uint underlyingBase;

    address[] traders;
    address router;
    address pool;
    address symbolAddr;
    string symbol;

    EthFeedMock feed;
    ERC20Mock erc20;
    ERC20Mock underlying;
    TimeProviderMock time;

    ProtocolSettings settings;
    CreditProvider creditProvider;
    CreditToken creditToken;
    OptionsExchange exchange;
    CollateralManager collateralManager;
    
    OptionsTrader bob;
    OptionsTrader alice;

    uint120[] x;
    uint120[] y;
    uint256[3] bsStockSpread;
    
    IOptionsExchange.OptionType CALL = IOptionsExchange.OptionType.CALL;
    IOptionsExchange.OptionType PUT = IOptionsExchange.OptionType.PUT;

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
        deployer.deploy(address(this));

        time = TimeProviderMock(deployer.getContractAddress("TimeProvider"));
        feed = EthFeedMock(deployer.getContractAddress("UnderlyingFeed"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        creditProvider = CreditProvider(deployer.getContractAddress("CreditProvider"));
        creditToken = CreditToken(deployer.getContractAddress("CreditToken"));
        exchange = OptionsExchange(deployer.getContractAddress("OptionsExchange"));
        erc20 = ERC20Mock(deployer.getContractAddress("StablecoinA"));
        router = deployer.getContractAddress("SwapRouter");
        pool = exchange.createPool("DEFAULT", "TEST", false, address(0));
        collateralManager = CollateralManager(deployer.getContractAddress("CollateralManager"));
        erc20.reset();

        settings.setAllowedToken(address(erc20), 1, 1);
        settings.setUdlFeed(address(feed), 1);
        underlying = ERC20Mock(feed.getUnderlyingAddr());
        underlyingBase = 10 ** uint(underlying.decimals());
        underlying.reset();

        bob = createTrader();
        alice = createTrader();
        
        uint vol = feed.getDailyVolatility(182 days);
        lowerVol = feed.calcLowerVolatility(vol);
        upperVol = feed.calcUpperVolatility(vol);


        erc20.issue(address(this), 1000e18);
        erc20.approve(pool, 1000e18);
        IGovernableLiquidityPool(pool).depositTokens(address(this), address(erc20), 1000e18);
        
        //initialize proposal manager with set parameters propsoal data
        SimplePoolManagementProposal pp = new SimplePoolManagementProposal();
        pp.setExecutionBytes(
            abi.encodeWithSelector(
                bytes4(keccak256("setParameters(uint256,uint256,uint256,uint256,address,uint256)")),
                0,
                0,
                time.getNow() + 365 days,
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

        
        //vote on proposal
        IProposalWrapper(proposalWrapperAddr).castVote(true);
        //close proposal
        IProposalWrapper(proposalWrapperAddr).close();
        IGovernableLiquidityPool(pool).withdraw(1000e18);

        feed.setPrice(ethInitialPrice);
        time.setTimeOffset(0);

    }

    function createTrader() internal returns (OptionsTrader) {

        OptionsTrader td = new OptionsTrader(address(exchange), pool, address(settings), address(collateralManager), address(creditProvider), address(time), address(feed));
        traders.push(address(td));
        return td;
    }

    function depositTokens(address to, uint value) internal {
        
        erc20.issue(address(this), value);
        erc20.approve(address(exchange), value);
        exchange.depositTokens(to, address(erc20), value);
    }

    function getBookLength() internal view returns (uint total) {
    /*
        returns (
            string memory symbols,
            address[] memory tokens,
            uint[] memory holding,
            uint[] memory written,
            uint[] memory uncovered,
            int[] memory iv,
            address[] memory underlying
        )
    */
        total = 0;
        for (uint i = 0; i < traders.length; i++) {
            (,,uint[] memory holding,,,,) = exchange.getBook(traders[i]);
            total += holding.length;
        }
    }

    function addSymbol(uint strike, uint maturity) internal {

        x = [400e18, 450e18, 500e18, 550e18, 600e18, 650e18, 700e18];
        y = [
            30e18,  40e18,  50e18,  50e18, 110e18, 170e18, 230e18,
            25e18,  35e18,  45e18,  45e18, 105e18, 165e18, 225e18
        ];

        bsStockSpread = [
            100 * volumeBase, // buy stock
            200 * volumeBase,  // sell stock
            5e7 //5%
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

    function liquidateAndRedeem(address _tk) internal {

        collateralManager.liquidateExpired(_tk, traders);
        OptionToken(_tk).redeem(traders);
    }
}