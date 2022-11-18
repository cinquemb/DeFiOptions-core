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
    }
    function listPoolsData(address account) external view returns (poolData memory);
    function listProposals() external view returns (proposalData memory);
}