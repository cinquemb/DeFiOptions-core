pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


interface ID8xPerpetualsContractInterface {

    //     iPerpetualId          global id for perpetual
    //     traderAddr            address of trader
    //     brokerSignature       signature of broker (or 0)
    //     brokerFeeTbps         broker can set their own fee
    //     fAmount               amount in base currency to be traded
    //     fLimitPrice           limit price
    //     fTriggerPrice         trigger price. Non-zero for stop orders.
    //     iDeadline             deadline for price (seconds timestamp)
    //     traderMgnTokenAddr    address of the compatible margin token the user likes to use,
    //                           0 if same token as liquidity pool's margin token
    //     flags                 trade flags
    struct ClientOrder {
        uint32 flags;
        uint24 iPerpetualId;
        uint16 brokerFeeTbps;
        address traderAddr;
        address brokerAddr;
        address referrerAddr;
        bytes brokerSignature;
        int128 fAmount;
        int128 fLimitPrice;
        int128 fTriggerPrice;
        int128 fLeverage; // 0 if deposit and trade separate
        uint64 iDeadline;
        uint64 createdTimestamp;
        //uint64 submittedBlock <- will be set by LimitOrderBook
        bytes32 parentChildDigest1;
        bytes32 parentChildDigest2;
    }

    struct LiquidityPoolData {
        bool isRunning; // state
        uint8 iPerpetualCount; // state
        uint8 id; // parameter: index, starts from 1
        uint16 iTargetPoolSizeUpdateTime; //parameter: timestamp in seconds. How often we update the pool's target size
        address marginTokenAddress; //parameter: address of the margin token
        // -----
        int128 fFundAllocationNormalizationCC; // state: sum of all perpetual weights during fund allocation (cheaper than re-normalizing w/each trade)
        int128 fDefaultFundCashCC; // state: profit/loss
        // -----
        uint64 prevAnchor; // state: keep track of timestamp since last withdrawal was initiated
        int32 fRedemptionRate; // state: used for settlement in case of AMM default
        address shareTokenAddress; // parameter
        // -----
        int128 fPnLparticipantsCashCC; // state: addLiquidity/withdrawLiquidity + profit/loss - rebalance
        int128 fAMMFundCashCC; // state: profit/loss - rebalance (sum of cash in individual perpetuals)
        // -----
        int128 fTargetAMMFundSize; // state: target AMM pool size for all perpetuals in pool (sum)
        int128 fTargetDFSize; // state: target default fund size for all perpetuals in pool
        // -----
        int128 fMaxTransferPerConvergencePeriod; // param: how many funds can be transferred in FUND_TRANSFER_CONVERGENCE_HOURS hours
        int128 fBrokerCollateralLotSize; // param:how much collateral do brokers deposit when providing "1 lot" (not trading lot)
        // -----
        uint128 prevTokenAmount; // state
        uint128 nextTokenAmount; // state
        // -----
        uint128 totalSupplyShareToken; // state
    }
    
    /**
     * @notice  D8X Perpetual Data structure to store user margin information.
     */
    struct MarginAccount {
        int128 fLockedInValueQC; // unrealized value locked-in when trade occurs in
        int128 fCashCC; // cash in collateral currency (base, quote, or quanto)
        int128 fPositionBC; // position in base currency (e.g., 1 BTC for BTCUSD)
        int128 fUnitAccumulatedFundingStart; // accumulated funding rate
        uint64 iLastOpenTimestamp; // timestamp in seconds when the position was last opened/increased
        uint16 feeTbps; // exchange fee in tenth of a basis point
        uint16 brokerFeeTbps; // broker fee in tenth of a basis point
        bytes16 positionId; // unique id for the position (for given trader, and perpetual). Current position, zero otherwise.
    }

    /**
     * @notice  Data structure to return simplified and relevant margin information.
     */
    struct D18MarginAccount {
        int256 lockedInValueQCD18; // unrealized value locked-in when trade occurs in
        int256 cashCCD18; // cash in collateral currency (base, quote, or quanto)
        int256 positionSizeBCD18; // position in base currency (e.g., 1 BTC for BTCUSD)
        bytes16 positionId; // unique id for the position (for given trader, and perpetual). Current position, zero otherwise.
    }
    
    function postOrder(ClientOrder calldata _order, bytes calldata _signature)
        external;

    function getMarginAccount(uint24 _perpetualId, address _traderAddress)
        external
        view
        returns (MarginAccount memory);

    function getMaxSignedOpenTradeSizeForPos(
        uint24 _perpetualId,
        int128 _fCurrentTraderPos,
        bool _isBuy
    ) external view returns (int128);

    function getPriceInfo(uint24 _perpetualId) external view returns (bytes32[] memory, bool[] memory);

    function getPoolCount() external view returns (uint8);
   
    /**

     * Query liquidity pool data for given indices

     * @param _poolFromIdx start from (>=1)

     * @param _poolToIdx up to (can be larger than number of pools)

     * @return array with liquidity pool data

     */

    function getLiquidityPools(uint8 _poolFromIdx, uint8 _poolToIdx) external view returns (LiquidityPoolData[] memory);

}