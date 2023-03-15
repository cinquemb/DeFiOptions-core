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

    struct OpenExposureVars {
        string symbol;
        uint vol;
        bool isCovered;
        address poolAddr;
        address[] _tokens;
        uint[] _uncovered;
        uint[] _holding;
    }

    struct OpenExposureInputs {
        string[] symbols;
        uint[] volume;
        bool[] isShort;
        bool[] isCovered;
        address[] poolAddrs;
        address[] paymentTokens;
    }

    function volumeBase() external view returns (uint);
    function collateral(address owner) external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function createPool(string calldata nameSuffix, string calldata symbolSuffix) external returns (address pool);
    function resolveToken(string calldata symbol) external view returns (address);
    function getExchangeFeeds(address udlFeed) external view returns (FeedData memory);
    function getFeedData(address udlFeed) external view returns (FeedData memory fd);
    function getBook(address owner) external view returns (string memory symbols, address[] memory tokens, uint[] memory holding, uint[] memory written, uint[] memory uncovered, int[] memory iv, address[] memory underlying);
    function getOptionData(address tkAddr) external view returns (IOptionsExchange.OptionData memory);
    function calcExpectedPayout(address owner) external view returns (int payout);
    function calcIntrinsicValue(address udlFeed, OptionType optType, uint strike, uint maturity) external view returns (int);
    function calcIntrinsicValue(OptionData calldata opt) external view returns (int value);
    function calcCollateral(address owner, bool is_regular) external view returns (uint);
    function calcCollateral(address udlFeed, uint volume, OptionType optType, uint strike,  uint maturity) external view returns (uint);
    function openExposure(
        OpenExposureInputs calldata oEi,
        address to
    ) external;
    function transferBalance(address to, uint value) external;
    function poolSymbols(uint index) external view returns (string memory);
    function totalPoolSymbols() external view returns (uint);
    function getPoolAddress(string calldata poolSymbol) external view returns (address);
    function transferBalance(address from, address to, uint value) external;
    function getOptionSymbol(OptionData calldata opt) external view returns (string memory symbol);
    function cleanUp(address owner, address _tk) external;
    function release(address owner, uint udl, uint coll) external;
    function depositTokens(address to, address token, uint value) external;
    function transferOwnership(string calldata symbol, address from, address to, uint value) external;
    function burn(address owner, uint value, address _tk) external;
}