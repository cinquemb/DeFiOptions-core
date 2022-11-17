pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IProtocolReader {
    struct poolData {
      string[] poolSymbols;
      address[] poolAddrs;
      uint[] poolApy;
      uint[] poolBalance;
      uint[] poolFreeBalance;
      uint[] userPoolBalance;
      uint[] userPoolUsdValue;
      uint[] poolMaturityDate;
      uint[] poolWithdrawalFee;
      string[] poolSymbolList;
    }
    function listPoolsData(address account) external view returns (poolData memory);
}