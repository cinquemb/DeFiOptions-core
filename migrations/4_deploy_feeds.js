const feed = artifacts.require("ChainlinkFeed");

/*

MUMBAI CHAINLINK AGGV3's
BTC / USD   0x007A22900a3B98143368Bd5906f8E17e9867581b
ETH / USD   0x0715A7794a1dc8e42615F059dD6e406A6594651A
LINK / MATIC  0x12162c3E810393dEC01362aBf156D7ecf6159528
MATIC / USD   0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada

*/

module.exports = async function(deployer) {

  // cont btc = await deployer.deploy(
  //   feed, 
  //   "BTC/USD",
  //   "0xd3a691c852cdb01e281545a27064741f0b7f6825",
  //   "0x007A22900a3B98143368Bd5906f8E17e9867581b",
  //   "0x83Aab4ED07630373b80955bcA600Dbb3462612C0",
  //   3 * 60 * 60,
  //   [],
  //   []
  // );
  // console.log("btc chainlink feed is at: "+ btc.address);


  // const eth = await deployer.deploy(
  //   feed, 
  //   "ETH/USD",
  //   "0xd0a1e359811322d97991e03f863a0c30c2cf029c",
  //   "0x0715A7794a1dc8e42615F059dD6e406A6594651A",
  //   "0x83Aab4ED07630373b80955bcA600Dbb3462612C0",
  //   3 * 60 * 60,
  //   [],
  //   []
  // );
  ///  console.log("eth chainlink feed is at: "+ eth.address);


  // const matic = await deployer.deploy(
  //   feed, 
  //   "MATIC/USD",
  //   "0x0000000000000000000000000000000000000000",
  //   "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada",
  //   "0x83Aab4ED07630373b80955bcA600Dbb3462612C0",
  //   3 * 60 * 60,
  //   [],
  //   []
  // );
  //  console.log("matic chainlink feed is at: "+ matic.address);

};