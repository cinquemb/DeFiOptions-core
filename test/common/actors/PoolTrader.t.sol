pragma solidity >=0.6.0;

import "../../../contracts/finance/OptionsExchange.sol";
import "../../../contracts/interfaces/IERC20.sol";
import "../../../contracts/interfaces/ILiquidityPool.sol";
import "../../../contracts/interfaces/IOptionsExchange.sol";

contract PoolTrader {
    
    IERC20 private erc20;
    OptionsExchange private exchange;
    ILiquidityPool private pool;
    
    address private addr;
    address private feed;
    uint private volumeBase = 1e18;
    
    constructor(address _erc20, address _exchange, address _pool, address _feed) public {

        erc20 = IERC20(_erc20);
        exchange = OptionsExchange(_exchange);
        pool = ILiquidityPool(_pool);
        addr = address(this);
        feed = _feed;
    }
    
    function balance() external view returns (uint) {
        
        return erc20.balanceOf(addr) + exchange.balanceOf(addr);
    }
    
    function approve(address spender, uint value) external {
        
        erc20.approve(spender, value);
    }

    function depositInExchange(uint value) external {

        erc20.approve(address(exchange), value);
        exchange.depositTokens(address(this), address(erc20), value);
    }

    function writeOptions(
        uint volume,
        IOptionsExchange.OptionType optType,
        uint strike, 
        uint maturity
    )
        public
        returns (address _tk)
    {
        _tk = exchange.createSymbol(
            feed,
            optType,
            strike, 
            maturity
        );

        IOptionsExchange.OpenExposureInputs memory oEi;

        oEi.symbols = new string[](1);
        oEi.volume = new uint[](1);
        oEi.isShort = new bool[](1);
        oEi.isCovered = new bool[](1);
        oEi.poolAddrs = new address[](1);
        oEi.paymentTokens = new address[](1);


        oEi.symbols[0] = IOptionToken(_tk).symbol();
        oEi.volume[0] = volume * volumeBase;
        oEi.isShort[0] = true;
        oEi.poolAddrs[0] = address(this);//poolAddr;
        //oEi.isCovered[0] = false; //expoliting default to save gas
        //oEi.paymentTokens[0] = address(0); //exploiting default to save gas


        exchange.openExposure(
            oEi,
            address(this)
        );
    }

    function withdrawFromPool() external {

        pool.withdraw(IERC20(address(pool)).balanceOf(address(this)));
    }
    
    function buyFromPool(string calldata symbol, uint price, uint volume)
        external
        returns (address)
    {    
        erc20.approve(address(pool), price * volume / volumeBase);
        return pool.buy(symbol, price, volume, address(erc20));
    }
    
    function sellToPool(string calldata symbol, uint price, uint volume) external {
        
        IERC20(exchange.resolveToken(symbol)).approve(address(pool), price * volume / volumeBase);
        pool.sell(symbol, price, volume);
    }
    
    function withdrawTokens(uint amount) public {
        address[] memory tks = new address[](1);
        tks[0] = address(erc20);

        uint[] memory tksAmt = new uint[](1);
        tksAmt[0] = amount;
        exchange.withdrawTokens(tks, tksAmt);
    }
}