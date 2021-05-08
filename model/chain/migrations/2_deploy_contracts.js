const Deployer4 = artifacts.require("Deployer");

const TimeProviderMock = artifacts.require("TimeProviderMock");
const ProtocolSettings = artifacts.require("ProtocolSettings");
const GovToken = artifacts.require("GovToken");

const CreditToken = artifacts.require("CreditToken");
const CreditProvider = artifacts.require("CreditProvider");
const OptionTokenFactory = artifacts.require("OptionTokenFactory");
const OptionsExchange = artifacts.require("OptionsExchange");

const LinearLiquidityPoolFactory = artifacts.require("LinearLiquidityPoolFactory");

const MockChainLinkFeed = artifacts.require("ChainlinkFeed");
const AggregatorV3Mock = artifacts.require("AggregatorV3Mock");


module.exports = async function(deployer) {

  await deployer.deploy(Deployer4, "0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000");

  const deployer4 = await Deployer4.at(Deployer4.address);
  console.log("Deployer4 is at: "+ Deployer4.address);
  const timeProvider = await deployer.deploy(TimeProviderMock, Deployer4.address);
  console.log("timeProvider is at: "+ timeProvider.address);
  const settings = await deployer.deploy(ProtocolSettings, Deployer4.address);
  console.log("settings is at: "+ settings.address);
  await deployer.deploy(CreditToken, Deployer4.address);
  await deployer.deploy(GovToken, Deployer4.address);
  const creditProvider = await deployer.deploy(CreditProvider, Deployer4.address);
  console.log("creditProvider is at: "+ creditProvider.address);
  await deployer.deploy(OptionTokenFactory, Deployer4.address);
  const exchange = await deployer.deploy(OptionsExchange, Deployer4.address);
  console.log("exchange is at: "+ exchange.address);
  const poolFactory = await deployer.deploy(LinearLiquidityPoolFactory, Deployer4.address);

  console.log("poolFactory is at: "+ poolFactory.address);


  const BTCUSDAgg = await deployer.deploy(AggregatorV3Mock);
  console.log("BTCUSDAgg is at: "+ BTCUSDAgg.address);
  const ETHUSDAgg = await deployer.deploy(AggregatorV3Mock);
  console.log("ETHUSDAgg is at: "+ ETHUSDAgg.address);

  /* TODO: Need to deply mock aggregator contracts for btc/usd and eth/usd first
  and use the contract addresses for as arguments into the chaninlink feed*/

  const BTCUSDMockFeed = await deployer.deploy(
    MockChainLinkFeed, 
    "BTC/USD", 
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
    ETHUSDAgg.address, //eth/usd feed mock
    timeProvider.address, //time provider address
    0,//offset
    [],
    []
  );
  console.log("ETHUSDMockFeed is at: "+ ETHUSDMockFeed.address);

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
};
