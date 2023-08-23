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

import "../../../contracts/feeds/DEXFeedFactory.sol";
import "../../../contracts/pools/LinearLiquidityPoolFactory.sol";
import "../../../contracts/pools/LinearAnySlopeInterpolator.sol";

import "../../../contracts/finance/credit/UnderlyingCreditProviderFactory.sol";
import "../../../contracts/finance/credit/UnderlyingCreditTokenFactory.sol";
import "../../../contracts/governance/ProtocolSettings.sol";
import "../../../contracts/governance/ProposalsManager.sol";
import "../../../contracts/governance/GovToken.sol";
import "../../common/actors/CreditHolder.t.sol";
import "../../common/mock/ERC20Mock.t.sol";
import "../../common/mock/EthFeedMock.t.sol";
import "../../common/mock/TimeProviderMock.t.sol";
import "../../common/mock/UniswapV2RouterMock.t.sol";

contract Base {
    
    TimeProviderMock time;
    ProtocolSettings settings;
    CreditProvider creditProvider;
    CreditToken creditToken;
    ERC20Mock erc20;
    
    CreditHolder issuer;
    CreditHolder alpha;
    CreditHolder beta;
    
    uint cBase = 1e8; // comparison base
    uint timeBase = 1 hours;


    /*

    await d.setContractAddress("ProtocolSettings", settings.address);
      await d.setContractAddress("TimeProvider", timeProvider.address);
      await d.setContractAddress("CreditProvider", creditProvider.address);
      await d.addAlias("CreditIssuer", "CreditProvider");
      await d.setContractAddress("CreditToken", ct.address);
      
      await d.setContractAddress("YieldTracker", yt.address);
      await d.setContractAddress("MetavaultHedgingManagerFactory", mvHedgingManagerFactory.address);
      await d.setContractAddress("D8xHedgingManagerFactory", d8xHedgingManagerFactory.address);
      await d.setContractAddress("ProtocolReader", pr.address);
      await d.setContractAddress("PendingExposureRouter", per.address);

      */

    function setUp() public {
    //function beforeEachDeploy() public {
        Deployer deployer = new Deployer(address(this));

        //deployer.reset();
        //if (!deployer.hasKey("CreditIssuer")) {
        deployer.setContractAddress("CreditIssuer", address(new CreditHolder()));
        //}
        
        deployer.setContractAddress("ProtocolSettings", address(new ProtocolSettings(true)));
        deployer.setContractAddress("TimeProvider", address(new TimeProviderMock()));
        deployer.setContractAddress("CreditProvider", address(new CreditProvider()));
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



        deployer.setContractAddress("StablecoinA", address(new ERC20Mock(18)), false);


        deployer.deploy(address(this));
        
        time = TimeProviderMock(deployer.getContractAddress("TimeProvider"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        creditProvider = CreditProvider(deployer.getContractAddress("CreditProvider"));
        creditToken = CreditToken(deployer.getContractAddress("CreditToken"));
        erc20 = ERC20Mock(deployer.getContractAddress("StablecoinA"));
        
        erc20.reset();

        settings.setAllowedToken(address(erc20), 1, 1);
        
        issuer = CreditHolder(deployer.getContractAddress("CreditIssuer"));
        alpha = new CreditHolder();
        beta = new CreditHolder();

        issuer.setCreditToken(address(creditToken));
        alpha.setCreditToken(address(creditToken));
        beta.setCreditToken(address(creditToken));

        time.setTimeOffset(0);
    }

    function addErc20Stock(uint value) internal {
        
        erc20.issue(address(this), value);
        erc20.approve(address(creditProvider), value);
        creditProvider.depositTokens(address(this), address(erc20), value);
    }
}