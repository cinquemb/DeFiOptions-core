pragma solidity >=0.6.0;

interface ILiquidityPool {

    event AddSymbol(string optSymbol);
    
    event RemoveSymbol(string optSymbol);

    event Buy(address indexed token, address indexed buyer, uint price, uint volume);
    
    event Sell(address indexed token, address indexed seller, uint price, uint volume);

    function maturity() external view returns (uint);

    function getOwner() external view returns (address);

    function yield(uint dt) external view returns (uint y);

    function depositTokens(address to, address token, uint value) external;

    function listSymbols() external view returns (string memory available);

    function queryBuy(string calldata optSymbol) external view returns (uint price, uint volume);

    function querySell(string calldata optSymbol) external view returns (uint price, uint volume);

    function buy(string calldata optSymbol, uint price, uint volume, address token)
        external
        returns (address addr);

    function sell(string calldata optSymbol, uint price, uint volume) external;
}
