pragma solidity >=0.6.0;

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

import "../../common/actors/OptionsTrader.t.sol";
import "../../common/mock/ERC20Mock.t.sol";
import "../../common/mock/EthFeedMock.t.sol";
import "../../common/mock/TimeProviderMock.t.sol";
import "../../common/mock/UniswapV2RouterMock.t.sol";

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
    
    IOptionsExchange.OptionType CALL = IOptionsExchange.OptionType.CALL;
    IOptionsExchange.OptionType PUT = IOptionsExchange.OptionType.PUT;

    Deployer deployer = new Deployer(address(0));

    
    //function beforeEachDeploy() public {
    function setUp() public {

        Deployer deployer = new Deployer(address(this));

        //deployer.reset();
        //if (!deployer.hasKey("CreditIssuer")) {
        //deployer.setContractAddress("CreditIssuer", address(new CreditHolder()));
        //}
        
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

        feed.setPrice(ethInitialPrice);
        time.setTimeOffset(0);
    }

    function createTrader() internal returns (OptionsTrader) {

        OptionsTrader td = new OptionsTrader(address(exchange), address(settings), address(collateralManager), address(creditProvider), address(time), address(feed));
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

    function liquidateAndRedeem(address _tk) internal {

        collateralManager.liquidateExpired(_tk, traders);
        OptionToken(_tk).redeem(traders);
    }
}