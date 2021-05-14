pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IOptionsExchange {
    enum OptionType { CALL, PUT }
    
    struct OptionData {
        address udlFeed;
        OptionType _type;
        uint120 strike;
        uint32 maturity;
    }

    function volumeBase() external view returns (uint);
    function collateral(address owner) external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function resolveToken(string calldata symbol) external view returns (address);
    function calcExpectedPayout(address owner) external view returns (int payout);
    function calcIntrinsicValue(address udlFeed, OptionType optType, uint strike, uint maturity) external view returns (int);
    function calcCollateral(address owner, bool is_regular) external view returns (uint);
    function calcCollateral(address udlFeed, uint volume, OptionType optType, uint strike,  uint maturity) external view returns (uint);
    function writeOptions(address udlFeed, uint volume, OptionType optType, uint strike,  uint maturity, address to) external returns (address _tk);
    function transferBalance(address to, uint value) external;
    function transferBalance(address from, address to, uint value) external;
    function getOptionSymbol(OptionData calldata opt) external view returns (string memory symbol);
    function cleanUp(address _tk, address owner, uint volume) external;
    function transferOwnership(string calldata symbol, address from, address to, uint value) external;
}