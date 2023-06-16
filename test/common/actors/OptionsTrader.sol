pragma solidity >=0.6.0;

import "../../../contracts/finance/OptionsExchange.sol";
import "../../../contracts/finance/CreditProvider.sol";
import "../../../contracts/interfaces/TimeProvider.sol";
import "../../../contracts/interfaces/UnderlyingFeed.sol";
import "../../../contracts/interfaces/IOptionsExchange.sol";
import "../../../contracts/interfaces/IOptionToken.sol";

contract OptionsTrader {
    
    OptionsExchange private exchange;
    CreditProvider private creditProvider;
    TimeProvider private time;
    
    address private addr;
    address private feed;
    uint private volumeBase = 1e18;
    
    constructor(address _exchange, address _credit_provider, address _time, address _feed) public {

        exchange = OptionsExchange(_exchange);
        creditProvider = CreditProvider(_credit_provider);
        time = TimeProvider(_time);
        addr = address(this);
        feed = _feed;
    }
    
    function balance() public view returns (uint) {
        
        return exchange.balanceOf(addr);
    }
    
    function approve(address spender, uint value) public {
        
        exchange.approve(spender, value);
    }
    
    function withdrawTokens() public {
        
        exchange.withdrawTokens(calcSurplus());
    }
    
    function withdrawTokens(uint amount) public {
        
        exchange.withdrawTokens(amount);
    }

    function writeOption(
        IOptionsExchange.OptionType optType,
        int strike, 
        uint timeTomaturity
    )
        public
        returns (address _tk)
    {
        _tk = writeOptions(1, optType, strike, timeTomaturity);
    }

    function writeOptions(
        uint volume,
        IOptionsExchange.OptionType optType,
        int strike, 
        uint timeToMaturity
    )
        public
        returns (address _tk)
    {
        _tk = exchange.writeOptions(
            feed,
            volume * volumeBase,
            optType,
            uint(strike),
            time.getNow() + timeToMaturity,
            address(this)
        );
    }

    function liquidateOptions(address _tk) public {
        
        exchange.liquidateOptions(_tk, address(this));
    }

    function transferOptions(address to, address _tk, uint volume) public {

        IOptionToken(_tk).transfer(to, volume * volumeBase);
    }

    function burnOptions(address _tk, uint volume) public {

        IOptionToken(_tk).burn(volume * volumeBase);
    }
    
    function calcCollateral() public view returns (uint) {
        
        return exchange.calcCollateral(addr);
    }
    
    function calcSurplus() public view returns (uint) {
        
        return exchange.calcSurplus(addr);
    }
    
    function calcDebt() public view returns (uint) {
        
        return creditProvider.calcDebt(addr);
    }

    function queryBuy(string memory symbol)
        public
        view
        returns (uint price, uint volume)
    {
        price = uint(exchange.calcIntrinsicValue(
            exchange.resolveToken(symbol)
        ));
        volume = 0;
    }

    function querySell(string memory symbol)
        public
        view
        returns (uint price, uint volume)
    {    
        price = uint(exchange.calcIntrinsicValue(
            exchange.resolveToken(symbol)
        ));
        volume = 0;
    }
}