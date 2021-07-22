pragma solidity >=0.6.0;

import "../interfaces/IOptionsExchange.sol";


interface ILiquidityPool {

    enum Operation { NONE, BUY, SELL }

    struct PricingParameters {
        address udlFeed;
        IOptionsExchange.OptionType optType;
        uint120 strike;
        uint32 maturity;
        uint32 t0;
        uint32 t1;
        uint[3] bsStockSpread; //buyStock == bsStockSpread[0], sellStock == bsStockSpread[1], spread == bsStockSpread[2]
        uint120[] x;
        uint120[] y;
    }

    struct Range {
        uint120 start;
        uint120 end;
    }

    event AddSymbol(string optSymbol);
    
    event RemoveSymbol(string optSymbol);

    event Buy(address indexed token, address indexed buyer, uint price, uint volume);
    
    event Sell(address indexed token, address indexed seller, uint price, uint volume);

    function maturity() external view returns (uint);

    function getOwner() external view returns (address);

    function yield(uint dt) external view returns (uint);

    function depositTokens(address to, address token, uint value) external;

    function listSymbols() external view returns (string memory available);

    function queryBuy(string calldata optSymbol) external view returns (uint price, uint volume);

    function querySell(string calldata optSymbol) external view returns (uint price, uint volume);

    function buy(
        string calldata optSymbol,
        uint price,
        uint volume,
        address token,
        uint maxValue,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        returns (address addr);

    function buy(string calldata optSymbol, uint price, uint volume, address token)
        external
        returns (address addr);

    function sell(
        string calldata optSymbol,
        uint price,
        uint volume,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external;

    function sell(string calldata optSymbol, uint price, uint volume) external;
}
