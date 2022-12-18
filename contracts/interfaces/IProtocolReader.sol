pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../interfaces/IProposalWrapper.sol";

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
    struct proposalData {
      address[] addr;
      address[] wrapperAddr;
      address[] govToken;
      IProposalWrapper.VoteType[] voteType;
      IProposalWrapper.Status[] status;
      bool[] isActive;

    }
    struct poolOptions {
      string[] poolSymbols;
      address[] poolAddrs;
      string[] poolOptionsRaw;
    }
    struct poolPricesData {
      //address[] poolAddrs;
      uint[] poolBuyPrice;
      uint[] poolSellPrice;
      uint[] poolBuyPriceVolume;
      uint[] poolSellPriceVolume;
    }
    function listPoolsData(address account) external view returns (poolData memory);
    function listProposals() external view returns (proposalData memory);
    function listPoolOptions() external view returns (poolOptions memory);
    function listPoolsPrices(string calldata optionSymbol, address[] calldata poolAddressList) external view returns (poolPricesData memory);
}