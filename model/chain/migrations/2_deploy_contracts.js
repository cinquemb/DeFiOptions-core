const Deployer4 = artifacts.require("Deployer");

const TimeProviderMock = artifacts.require("TimeProviderMock");
const ProtocolSettings = artifacts.require("ProtocolSettings");
const GovToken = artifacts.require("GovToken");

const CreditToken = artifacts.require("CreditToken");
const CreditProvider = artifacts.require("CreditProvider");
const OptionTokenFactory = artifacts.require("OptionTokenFactory");
const OptionsExchange = artifacts.require("OptionsExchange");

const LinearLiquidityPool = artifacts.require("LinearLiquidityPool");

const MockChainLinkFeed = artifacts.require("ChainlinkFeed");
const AggregatorV3Mock = artifacts.require("AggregatorV3Mock");


module.exports = async function(deployer) {

  await deployer.deploy(Deployer4, "0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000");
  console.log("Deployer4 is at: "+ Deployer4.address);
  const timeProvider = await deployer.deploy(TimeProviderMock, Deployer4.address);
  console.log("timeProvider is at: "+ timeProvider.address);
  const settings = await deployer.deploy(ProtocolSettings, Deployer4.address);
  console.log("settings is at: "+ settings.address);
  await deployer.deploy(CreditToken, Deployer4.address);
  await deployer.deploy(GovToken, Deployer4.address);
  await deployer.deploy(CreditProvider, Deployer4.address);
  await deployer.deploy(OptionTokenFactory, Deployer4.address);
  const exchange = await deployer.deploy(OptionsExchange, Deployer4.address);
  console.log("exchange is at: "+ exchange.address);
  const pool = await deployer.deploy(LinearLiquidityPool, Deployer4.address);

  console.log("pool is at: "+ pool.address);


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
    3 * 60 * 60,
    [],
    []
  );

  const ETHUSDMockFeed = await deployer.deploy(
    MockChainLinkFeed, 
    "ETH/USD", 
    ETHUSDAgg.address, //eth/usd feed mock
    timeProvider.address, //time provider address
    3 * 60 * 60,
    [],
    []
  );



  
  /*
      const roundIds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  const answers = [20e18, 25e18, 28e18, 18e18, 19e18, 12e18, 12e18, 13e18, 18e18, 20e18];
        updatedAts = 
            [1 days, 2 days, 3 days, 4 days, 5 days, 6 days, 7 days, 8 days, 9 days, 10 days];

  AggregatorV3Mock mock = new AggregatorV3Mock();

    await mock.setRoundIds(roundIds);
    await mock.setAnswers(answers);
    await mock.setUpdatedAts(updatedAts);

      const await pool.setParameters(
        spread,
        reserveRatio,
        "90 days"
    );
      erc20 = new ERC20Mock();
      settings.setOwner(address(this));
      settings.setAllowedToken(address(erc20), 1, 1);
      settings.setDefaultUdlFeed(address(feed));
      settings.setUdlFeed(address(feed), 1);

      feed.setPrice(ethInitialPrice);
      time.setFixedTime(0);

  */

};
