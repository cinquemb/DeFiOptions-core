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
      gasPrice: 25000000000 // 25 nAVAX for now
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
    },

    mumbai: {
      provider: function() {
        return new HDWalletProvider(process.env.TESTNET_PRIVATE_KEY, "https://matic-mumbai.chainstacklabs.com/")
      },
      gas: 8000000,
      network_id: 80001,
      networkCheckTimeout: 1000000,
      timeoutBlocks: 200,
      from: "0xe977757dA5fd73Ca3D2bA6b7B544bdF42bb2CBf6",
      gasPrice: 401e8 // 50 gewi
    }
  },

  compilers: {
    solc: {
      version: "0.6.0",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
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
