const Deployer4 = artifacts.require("Deployer");
const Prox3 = artifacts.require("Proxy");
const MetavaultHedgingManagerFactory = artifacts.require("MetavaultHedgingManagerFactory");

module.exports = async function(deployer) {  
  /*
  var deployer4 = await Deployer4.deployed();

  const mvaddrOldProx3 = await deployer4.getContractAddress("MetavaultHedgingManagerFactory");
  const mvInstance = await Prox3.at(mvaddrOldProx3);


  const mvHedgingManagerFactory = await deployer.deploy(
    MetavaultHedgingManagerFactory, 
    "0x05374dE5263318d67835e7daAB0D36CA87bB4286", // address _positionManager
    "0xe232AA2304899513EA10cf0E813fe1b4075c1c45", //address _reader
    "0x0000000000000000000000000000000000000000" //bytes32 _referralCode
  );
  console.log("MetavaultHedgingManagerFactory is at: "+ mvHedgingManagerFactory.address);
  await mvInstance.setImplementation(mvHedgingManagerFactory.address);
  //await deployer4.setContractAddress("MetavaultHedgingManagerFactory", mvHedgingManagerFactory.address);

  const MetavaultHedgingManagerFactoryAddress = await deployer4.getContractAddress("MetavaultHedgingManagerFactory");
  console.log("MetavaultHedgingManagerFactoryAddress is at: "+ MetavaultHedgingManagerFactoryAddress);
*/
};
