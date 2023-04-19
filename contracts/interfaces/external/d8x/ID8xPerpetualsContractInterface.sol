pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../perpetual/interfaces/IClientOrder.sol";

interface ID8xPerpetualsContractInterface {
    
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
    
    function postOrder(IClientOrder.ClientOrder calldata _order, bytes calldata _signature)
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
}