pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IOptionsExchange.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IGovernableLiquidityPool.sol";
import "../interfaces/IProposalManager.sol";
import "../interfaces/IProposalWrapper.sol";


contract ProtocolReader is ManagedContract {

    IProtocolSettings private settings;
    IOptionsExchange private exchange;
    IProposalManager private proposalManager;

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

    event IncentiveReward(address indexed from, uint value);

    function initialize(Deployer deployer) override internal {
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
        proposalManager = IProposalManager(deployer.getContractAddress("ProposalsManager"));
    }

    function listPoolsData(address account) external view returns (poolData memory){
      
      uint poolSymbolsMaxLen = exchange.totalPoolSymbols();
      poolData memory pd;
      pd.poolSymbols = new string[](poolSymbolsMaxLen);
      pd.poolAddrs = new address[](poolSymbolsMaxLen);
      pd.poolApy = new uint[](poolSymbolsMaxLen);
      pd.poolBalance = new uint[](poolSymbolsMaxLen);
      pd.poolFreeBalance = new uint[](poolSymbolsMaxLen);
      pd.userPoolBalance = new uint[](poolSymbolsMaxLen);
      pd.userPoolUsdValue = new uint[](poolSymbolsMaxLen);
      pd.poolMaturityDate = new uint[](poolSymbolsMaxLen);
      pd.poolWithdrawalFee = new uint[](poolSymbolsMaxLen);
      pd.poolSymbolList = new string[](poolSymbolsMaxLen);


      for (uint i=0; i < poolSymbolsMaxLen; i++) {
          string memory pSym = exchange.poolSymbols(i);
          pd.poolSymbols[i] = pSym;
          address poolAddr = exchange.getPoolAddress(pSym);
          pd.poolAddrs[i] = poolAddr;
          try IGovernableLiquidityPool(poolAddr).yield(365 * 24 * 60 * 60) returns (uint v) {
              pd.poolApy[i] = v;
          } catch (bytes memory /*lowLevelData*/) {
              pd.poolApy[i] = 0;
          }
          pd.poolBalance[i] = exchange.balanceOf(poolAddr);
          pd.userPoolBalance[i] = IERC20(poolAddr).balanceOf(account);
          try IGovernableLiquidityPool(poolAddr).valueOf(account) returns (uint v) {
              pd.userPoolUsdValue[i] = v;
          } catch (bytes memory /*lowLevelData*/) {
              pd.userPoolUsdValue[i] = 0;
          }
          pd.poolFreeBalance[i] = IGovernableLiquidityPool(poolAddr).calcFreeBalance();
          pd.poolMaturityDate[i] = IGovernableLiquidityPool(poolAddr).maturity();
          pd.poolWithdrawalFee[i] = IGovernableLiquidityPool(poolAddr).withdrawFee();
          pd.poolSymbolList[i] = IGovernableLiquidityPool(poolAddr).listSymbols();
      }

      return pd;
    }

    function listProposals() external view returns (proposalData memory) {
      proposalData memory pd;
      uint totalProposals = proposalManager.proposalCount();

      pd.addr = new address[](totalProposals);
      pd.wrapperAddr = new address[](totalProposals);
      pd.govToken = new address[](totalProposals);
      pd.voteType = new IProposalWrapper.VoteType[](totalProposals);
      pd.status = new IProposalWrapper.Status[](totalProposals);
      pd.isActive = new bool[](totalProposals);

      for(uint i=1; i< totalProposals; i++){
        pd.addr[i] = proposalManager.resolveProposal(i);
        pd.wrapperAddr[i] = proposalManager.resolve(pd.addr[i]);
        pd.govToken[i] = IProposalWrapper(pd.wrapperAddr[i]).getGovernanceToken();
        pd.voteType[i] = IProposalWrapper(pd.wrapperAddr[i]).getVoteType();
        pd.status[i] = IProposalWrapper(pd.wrapperAddr[i]).getStatus();
        pd.isActive[i] = IProposalWrapper(pd.wrapperAddr[i]).isActive();
      }
      return pd;
    }
}