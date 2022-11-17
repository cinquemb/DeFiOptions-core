pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/IGovernableLiquidityPool.sol";

contract ProtocolReader is ManagedContract {

    IProtocolSettings private settings;
    IOptionsExchange private exchange;

    event IncentiveReward(address indexed from, uint value);

    function initialize(Deployer deployer) override internal {
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
    }

    function listPoolsData() external view returns (string[] memory, address[] memory){
      uint poolSymbolsMaxLen = exchange.totalPoolSymbols();
      string[] memory poolSymbols = new string[](poolSymbolsMaxLen);
      address[] memory poolAddrs = new address[](poolSymbolsMaxLen);
      for (uint i=0; i < poolSymbolsMaxLen; i++) {
          string memory pSym = exchange.poolSymbols(i);
          poolSymbols[i] = pSym;
          address poolAddr = exchange.getPoolAddress(pSym);
          poolAddrs[i] = poolAddr;
      }

      return (poolSymbols, poolAddrs);
    }
}