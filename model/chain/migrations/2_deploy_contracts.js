const Deployer4 = artifacts.require("Deployer");

const TimeProviderMock = artifacts.require("TimeProviderMock");
const ProtocolSettings = artifacts.require("ProtocolSettings")
const ProposalsManager = artifacts.require("ProposalsManager");
const GovToken = artifacts.require("GovToken");

const CreditToken = artifacts.require("CreditToken");
const CreditProvider = artifacts.require("CreditProvider");
const CollateralManager = artifacts.require("CollateralManager");
const MetavaultHedgingManagerFactory = artifacts.require("MetavaultHedgingManagerFactory");
const OptionTokenFactory = artifacts.require("OptionTokenFactory");
const OptionsExchange = artifacts.require("OptionsExchange");
const Incentivized = artifacts.require("Incentivized");

const DEXFeedFactory = artifacts.require("DEXFeedFactory");

const LinearLiquidityPoolFactory = artifacts.require("LinearLiquidityPoolFactory");
const LinearAnySlopeInterpolator = artifacts.require("LinearAnySlopeInterpolator");

const MockChainLinkFeed = artifacts.require("ChainlinkFeed");
const AggregatorV3Mock = artifacts.require("AggregatorV3Mock");
const YieldTracker = artifacts.require("YieldTracker");
const UnderlyingVault = artifacts.require("UnderlyingVault");

const ERC20 = artifacts.require("ERC20Mock");
const ProtocolReader = artifacts.require("ProtocolReader");



module.exports = async function(deployer) {
  //need to change address everytime network restarts

  const mAddr = "0x1552B37aaC78d7458BEDe858ccb578250173F0D1";
  await deployer.deploy(Deployer4, mAddr);

  const deployer4 = await Deployer4.at(Deployer4.address);
  console.log("Deployer4 is at: "+ Deployer4.address);
  const timeProvider = await deployer.deploy(TimeProviderMock);
  console.log("timeProvider is at: "+ timeProvider.address);
  const settings = await deployer.deploy(ProtocolSettings, false);
  console.log("settings is at: "+ settings.address);
  const ct = await deployer.deploy(CreditToken);
  const pm = await deployer.deploy(ProposalsManager);
  const gt = await deployer.deploy(GovToken, mAddr);
  const yt = await deployer.deploy(YieldTracker);
  const uv = await deployer.deploy(UnderlyingVault);
  const id = await deployer.deploy(Incentivized);
  const pr = await deployer.deploy(ProtocolReader);
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

  const mvHedgingManagerFactory = await deployer.deploy(
    MetavaultHedgingManagerFactory, 
    "0x0000000000000000000000000000000000000000", // address _positionManager
    "0x0000000000000000000000000000000000000000", //address _reader
    "0x0000000000000000000000000000000000000000" //bytes32 _referralCode
  );
  console.log("MetavaultHedgingManagerFactory is at: "+ mvHedgingManagerFactory.address);

  
  await deployer4.setContractAddress("TimeProvider", timeProvider.address);
  await deployer4.setContractAddress("CreditProvider", creditProvider.address);
  await deployer4.addAlias("CreditIssuer", "CreditProvider");
  await deployer4.setContractAddress("CreditToken", ct.address);
  await deployer4.setContractAddress("ProposalsManager", pm.address);
  await deployer4.setContractAddress("CollateralManager", collateralManager.address);
  await deployer4.setContractAddress("OptionsExchange", exchange.address);
  await deployer4.setContractAddress("OptionTokenFactory", otf.address);
  await deployer4.setContractAddress("GovToken", gt.address); //MAY JUST USE THE EXISTING GOV TOKEN ADDR ON POLYGON MAINNET TO MAKE THINGS SIMPLE
  await deployer4.setContractAddress("ProtocolSettings", settings.address);
  await deployer4.setContractAddress("LinearLiquidityPoolFactory", poolFactory.address);
  await deployer4.setContractAddress("DEXFeedFactory", dexFeedFactory.address);
  await deployer4.setContractAddress("Interpolator", lasit.address);
  await deployer4.setContractAddress("YieldTracker", yt.address);
  await deployer4.setContractAddress("UnderlyingVault", uv.address);
  await deployer4.setContractAddress("Incentivized", id.address);
  await deployer4.setContractAddress("MetavaultHedgingManagerFactory", mvHedgingManagerFactory.address);
  await deployer4.setContractAddress("ProtocolReader", pr.address);


  await deployer4.deploy();

  let settingContractsProxy = [
    {name:"ProtocolSettings", addr: null},
    {name:"TimeProvider", addr: null},
    {name:"CreditProvider", addr: null},
    {name:"CreditToken", addr: null},
    {name:"ProposalsManager", addr: null},
    {name:"CollateralManager", addr: null},
    {name:"OptionsExchange", addr: null},
    {name:"OptionTokenFactory", addr: null},
    {name:"GovToken", addr: null},
    {name:"LinearLiquidityPoolFactory", addr: null},
    {name:"DEXFeedFactory", addr: null},
    {name:"Interpolator", addr: null},
    {name:"YieldTracker", addr: null},
    {name:"UnderlyingVault", addr: null},
    {name:"Incentivized", addr: null},
    {name:"MetavaultHedgingManagerFactory", addr: null},
    {name:"ProtocolReader", addr:null}
  ];

  for(let node of settingContractsProxy){
      let proxAddr = await d.getContractAddress(node.name); 
      console.log(node.name + ": "+ proxAddr);
  }

  /* MOCK BELOW */

  const FakeDAI = await deployer.deploy(ERC20, 18, "FakeDAI");
  const FakeUSDC = await deployer.deploy(ERC20, 6, "FakeUSDC");
  const FakeBTC = await deployer.deploy(ERC20, 18, "FakeBTC");
  const FakeETH = await deployer.deploy(ERC20, 18, "FakeETH");

  const FakeDAI = await deployer.deploy(ERC20, 18, "FakeDAI");
  console.log("FakeDAI is at: "+ FakeDAI.address);
  const FakeUSDC = await deployer.deploy(ERC20, 6, "FakeUSDC");
  console.log("FakeUSDC is at: "+ FakeUSDC.address);
  const FakeBTC = await deployer.deploy(ERC20, 18, "FakeBTC");
  console.log("FakeBTC is at: "+ FakeBTC.address);
  const FakeETH = await deployer.deploy(ERC20, 18, "FakeETH");
  console.log("FakeETH is at: "+ FakeETH.address);

  const BTCUSDAgg = await deployer.deploy(AggregatorV3Mock);
  console.log("BTCUSDAgg is at: "+ BTCUSDAgg.address);
  const ETHUSDAgg = await deployer.deploy(AggregatorV3Mock);
  console.log("ETHUSDAgg is at: "+ ETHUSDAgg.address);
  const USDCAgg = await deployer.deploy(AggregatorV3Mock);
  console.log("USDCAgg is at: "+ USDCAgg.address);
};
