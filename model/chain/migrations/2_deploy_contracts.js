const Deployer4 = artifacts.require("Deployer");

const TimeProviderMock = artifacts.require("TimeProviderMock");
const ProtocolSettings = artifacts.require("ProtocolSettings");
const GovToken = artifacts.require("GovToken");

const CreditToken = artifacts.require("CreditToken");
const CreditProvider = artifacts.require("CreditProvider");
const CollateralManager = artifacts.require("CollateralManager");
const OptionTokenFactory = artifacts.require("OptionTokenFactory");
const OptionsExchange = artifacts.require("OptionsExchange");

const DEXFeedFactory = artifacts.require("DEXFeedFactory");

const LinearLiquidityPoolFactory = artifacts.require("LinearLiquidityPoolFactory");
const LinearAnySlopeInterpolator = artifacts.require("LinearAnySlopeInterpolator");

const MockChainLinkFeed = artifacts.require("ChainlinkFeed");
const AggregatorV3Mock = artifacts.require("AggregatorV3Mock");
const YieldTracker = artifacts.require("YieldTracker");
const UnderlyingVault = artifacts.require("UnderlyingVault");


module.exports = async function(deployer) {
  //need to change address everytime network restarts
  await deployer.deploy(Deployer4, "0xF5086ae5e1bec914506CeADe8139AF7B0F86be4d");

  const deployer4 = await Deployer4.at(Deployer4.address);
  console.log("Deployer4 is at: "+ Deployer4.address);
  const timeProvider = await deployer.deploy(TimeProviderMock);
  console.log("timeProvider is at: "+ timeProvider.address);
  const settings = await deployer.deploy(ProtocolSettings);
  console.log("settings is at: "+ settings.address);
  const ct = await deployer.deploy(CreditToken);
  const gt = await deployer.deploy(GovToken);
  const yt = await deployer.deploy(YieldTracker);
  const uv = await deployer.deploy(UnderlyingVault);
  const lasit = await deployer.deploy(LinearAnySlopeInterpolator);
  const creditProvider = await deployer.deploy(CreditProvider);
  console.log("creditProvider is at: "+ creditProvider.address);
  const otf = await deployer.deploy(OptionTokenFactory);
  const exchange = await deployer.deploy(OptionsExchange);
  console.log("exchange is at: "+ exchange.address);
  const poolFactory = await deployer.deploy(LinearLiquidityPoolFactory);
  console.log("poolFactory is at: "+ poolFactory.address);
  const dexFeedFactory = await deployer.deploy(DEXFeedFactory);
  console.log("dexFeedFactory is at: "+ dexFeedFactory.address);

  const collateralManager = await deployer.deploy(CollateralManager);


  const BTCUSDAgg = await deployer.deploy(AggregatorV3Mock);
  console.log("BTCUSDAgg is at: "+ BTCUSDAgg.address);
  const ETHUSDAgg = await deployer.deploy(AggregatorV3Mock);
  console.log("ETHUSDAgg is at: "+ ETHUSDAgg.address);

  /* TODO: Need to deply mock aggregator contracts for btc/usd and eth/usd first
  and use the contract addresses for as arguments into the chaninlink feed*/

  const BTCUSDMockFeed = await deployer.deploy(
    MockChainLinkFeed, 
    "BTC/USD",
    "0x0000000000000000000000000000000000000000",
    BTCUSDAgg.address,//btc/usd feed mock
    timeProvider.address, //time provider address
    0,//offset
    [],
    []
  );
  console.log("BTCUSDMockFeed is at: "+ BTCUSDMockFeed.address);

  const ETHUSDMockFeed = await deployer.deploy(
    MockChainLinkFeed, 
    "ETH/USD", 
    "0x0000000000000000000000000000000000000000",
    ETHUSDAgg.address, //eth/usd feed mock
    timeProvider.address, //time provider address
    0,//offset
    [],
    []
  );
  console.log("ETHUSDMockFeed is at: "+ ETHUSDMockFeed.address);
  
  await deployer4.setContractAddress("TimeProvider", timeProvider.address);
  await deployer4.setContractAddress("CreditProvider", creditProvider.address);
  await deployer4.addAlias("CreditIssuer", "CreditProvider");
  await deployer4.setContractAddress("CreditToken", ct.address);
  await deployer4.setContractAddress("CollateralManager", collateralManager.address);
  await deployer4.setContractAddress("OptionsExchange", exchange.address);
  await deployer4.setContractAddress("OptionTokenFactory", otf.address);
  await deployer4.setContractAddress("GovToken", gt.address);
  await deployer4.setContractAddress("ProtocolSettings", settings.address);
  await deployer4.setContractAddress("LinearLiquidityPoolFactory", poolFactory.address);
  await deployer4.setContractAddress("DEXFeedFactory", dexFeedFactory.address);
  await deployer4.setContractAddress("Interpolator", lasit.address);
  await deployer4.setContractAddress("YieldTracker", yt.address);
  await deployer4.setContractAddress("UnderlyingVault", uv.address);

  await deployer4.deploy();

  const timeProviderAddress = await deployer4.getContractAddress("TimeProvider");
  console.log("timeProviderAddress is at: "+ timeProviderAddress);
  const ProtocolSettingsAddress = await deployer4.getContractAddress("ProtocolSettings");
  console.log("ProtocolSettingsAddress is at: "+ ProtocolSettingsAddress);
  const CreditProviderAddress = await deployer4.getContractAddress("CreditProvider");
  console.log("CreditProviderAddress is at: "+ CreditProviderAddress);
  const OptionsExchangeAddress = await deployer4.getContractAddress("OptionsExchange");
  console.log("OptionsExchangeAddress is at: "+ OptionsExchangeAddress);
  const LinearLiquidityPoolFactoryAddress = await deployer4.getContractAddress("LinearLiquidityPoolFactory");
  console.log("LinearLiquidityPoolFactoryAddress is at: "+ LinearLiquidityPoolFactoryAddress);
  const DEXFeedFactoryAddress = await deployer4.getContractAddress("DEXFeedFactory");
  console.log("DEXFeedFactoryAddress is at: "+ DEXFeedFactoryAddress);
};
