pragma solidity >=0.6.0;

import "truffle/Assert.sol";
//import "truffle/DeployedAddresses.sol";
import "../../../contracts/deployment/Deployer.sol";
import "../../../contracts/finance/CreditProvider.sol";
import "../../../contracts/finance/OptionsExchange.sol";
import "../../../contracts/governance/ProposalsManager.sol";
import "../../../contracts/governance/ProposalWrapper.sol";
import "../../../contracts/governance/ProtocolSettings.sol";
import "../../../contracts/governance/GovToken.sol";
import "../../common/actors/ShareHolder.t.sol";
import "../../common/mock/ERC20Mock.t.sol";
import "../../common/mock/EthFeedMock.t.sol";
import "../../common/mock/TimeProviderMock.t.sol";
import "../../common/mock/UniswapV2RouterMock.t.sol";
import "../../common/samples/ChangeInterestRateProposal.t.sol";
import "../../common/samples/TransferBalanceProposal.t.sol";

contract Base {
    
    TimeProviderMock time;
    CreditProvider creditProvider;
    OptionsExchange exchange;
    ProtocolSettings settings;
    ProposalsManager manager;
    GovToken govToken;
    ERC20Mock erc20;
    
    ShareHolder alpha;
    ShareHolder beta;
    ShareHolder gama;

    ProposalWrapper.Quorum SIMPLE_MAJORITY = ProposalWrapper.Quorum.SIMPLE_MAJORITY;
    Deployer deployer = new Deployer(address(0));

    function beforeEachDeploy() public {

        //Deployer deployer = Deployer(DeployedAddresses.Deployer());
        deployer.reset();
        deployer.deploy(address(this));
        time = TimeProviderMock(deployer.getContractAddress("TimeProvider"));
        creditProvider = CreditProvider(deployer.getContractAddress("CreditProvider"));
        exchange = OptionsExchange(deployer.getContractAddress("OptionsExchange"));
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        manager = ProposalsManager(deployer.getContractAddress("ProposalsManager"));
        govToken = GovToken(deployer.getContractAddress("GovToken"));
        erc20 = ERC20Mock(deployer.getContractAddress("StablecoinA"));

        erc20.reset();
        
        settings.setCirculatingSupply(1 ether);
        settings.setAllowedToken(address(erc20), 1, 1);
        govToken.setChildChainManager(address(this));

        alpha = new ShareHolder(address(govToken), address(manager));
        beta = new ShareHolder(address(govToken), address(manager));
        gama = new ShareHolder(address(govToken), address(manager));
        
        govToken.deposit(address(alpha), abi.encode(1 ether));
        alpha.delegateTo(address(alpha));

        alpha.transfer(address(beta),  99 finney); //  9.9%
        beta.delegateTo(address(beta));

        alpha.transfer(address(gama), 410 finney); // 41.0%
        gama.delegateTo(address(gama));

        time.setTimeOffset(0);
    }

    function depositTokens(address to, uint value) internal {
        
        erc20.issue(address(this), value);
        erc20.approve(address(exchange), value);
        exchange.depositTokens(to, address(erc20), value);
    }
}