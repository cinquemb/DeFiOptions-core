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

    struct FeedData {
        uint120 lowerVol;
        uint120 upperVol;
    }

    function volumeBase() external view returns (uint);
    function collateral(address owner) external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function resolveToken(string calldata symbol) external view returns (address);
    function getExchangeFeeds(address udlFeed) external view returns (FeedData memory);
    function getFeedData(address udlFeed) external view returns (FeedData memory fd);
    function getBook(address owner) external view returns (string memory symbols, address[] memory tokens, uint[] memory holding, uint[] memory written, uint[] memory uncovered, int[] memory iv);
    function getOptionData(address tkAddr) external view returns (IOptionsExchange.OptionData memory);
    function calcExpectedPayout(address owner) external view returns (int payout);
    function calcIntrinsicValue(address udlFeed, OptionType optType, uint strike, uint maturity) external view returns (int);
    function calcIntrinsicValue(OptionData calldata opt) external view returns (int value);
    function getUdlPrice(IOptionsExchange.OptionData calldata opt) external view returns (int answer);
    function calcCollateral(address owner, bool is_regular) external view returns (uint);
    function calcCollateral(address udlFeed, uint volume, OptionType optType, uint strike,  uint maturity) external view returns (uint);
    function writeOptions(address udlFeed, uint volume, OptionType optType, uint strike,  uint maturity, address to) external returns (address _tk);
    function transferBalance(address to, uint value) external;
    function transferBalance(address from, address to, uint value) external;
    function underlyingBalance(address owner, address _tk) external view returns (uint);
    function getOptionSymbol(OptionData calldata opt) external view returns (string memory symbol);
    function cleanUp(address owner, address _tk) external;
    function release(address owner, uint udl, uint coll) external;
    function transferOwnership(string calldata symbol, address from, address to, uint value) external;
}