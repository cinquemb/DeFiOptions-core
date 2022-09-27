
const Deployer = artifacts.require("Deployer");
const MetavaultHedgingManager = artifacts.require("MetavaultHedgingManager");
const MetavaultPositionManager = artifacts.require("PositionManagerMock");
const MetavaultReader = artifacts.require("MetavaultReaderMock");

module.exports = async function(deployer) {
  
  /* MOCK BELOW */
  //const metavaultPositionManager = await deployer.deploy(MetavaultPositionManager);
  //console.log("metavaultPositionManager is at: "+ metavaultPositionManager.address);
  //const metavaultReader = await deployer.deploy(MetavaultReader);
  //console.log("metavaultReader is at: "+ metavaultReader.address);
  /* MOCK ABOVE */

  /*
  const mvHedgingManager = await deployer.deploy(
    MetavaultHedgingManager, 
    Deployer4.address, // address _deployAddr
    metavaultPositionManager.address, // address _positionManager
    metavaultReader.address, //address _reader
    "0x0000000000000000000000000000000000000000" //bytes32 _referralCode
  );
  console.log("MetaVaultHedgingManager is at: "+ mvHedgingManager.address);*/
};