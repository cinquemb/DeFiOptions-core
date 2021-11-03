const HDWalletProvider = require("@truffle/hdwallet-provider");
const Web3 = require('web3');

require('dotenv').config();

module.exports = {

  networks: {
    
    kovan: {
      provider: function() {
        return new HDWalletProvider(
          process.env.MNENOMIC,
          "wss://kovan.infura.io/ws/v3/" + process.env.INFURA_API_KEY
        )
      },
      network_id: 42,
      networkCheckTimeout: 1000000,
      timeoutBlocks: 200,
      gasPrice: 1e9 // 1 gewi
    },

    //for eth
    /*development: {
      host: "127.0.0.1",     // Localhost (default: none)
      port: 7545,            // Standard Ethereum port (default: none)
      network_id: "*",       // Any network (default: none)
      gas: 8000000,
    }*/

    development: {
      provider: () => new Web3.providers.HttpProvider('http://127.0.0.1:9545/ext/bc/C/rpc'),
      network_id: "*",
      gas: 8000000,
      gasPrice: 225000000000 // 225 nAVAX for now
    },
  
    matic: {
      provider: function() {
        return new HDWalletProvider(
          process.env.MNENOMIC,
          "https://polygon-mainnet.infura.io/v3/" + process.env.INFURA_API_KEY
        )
      },
      network_id: 137,
      networkCheckTimeout: 1000000,
      timeoutBlocks: 200,
      gasPrice: 50e9 // 50 gewi
    }
  },

  compilers: {
    solc: {
      version: "0.6.0",
      settings: {
        optimizer: {
          enabled: true,
          runs: 100
        }
      }
    }
  },
  /*
  plugins: [
    'truffle-plugin-verify',
    'truffle-contract-size'
  ],

  api_keys: {
    etherscan: process.env.ETHERSCAN_KEY
  }*/
};
