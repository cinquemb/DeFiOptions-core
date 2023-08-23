pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../../contracts/finance/OptionsExchange.sol";
import "../../../contracts/governance/ProtocolSettings.sol";
import "../../../contracts/finance/credit/CreditProvider.sol";
import "../../../contracts/interfaces/TimeProvider.sol";
import "../../../contracts/interfaces/UnderlyingFeed.sol";
import "../../../contracts/interfaces/ICollateralManager.sol";
import "../../../contracts/interfaces/IOptionsExchange.sol";
import "../../../contracts/interfaces/IOptionToken.sol";
import "../../../contracts/interfaces/IGovernableLiquidityPool.sol";

contract OptionsTrader {
    
    OptionsExchange private exchange;
    CreditProvider private creditProvider;
    TimeProvider private time;
    ProtocolSettings private settings;
    ICollateralManager private collateralManager;
    IGovernableLiquidityPool private pool;

    address private addr;
    address private feed;
    uint private volumeBase = 1e18;
    
    constructor(address _exchange, address _pool, address _protocol_settings, address _credit_provider, address _collateral_manager, address _time, address _feed) public {

        exchange = OptionsExchange(_exchange);
        creditProvider = CreditProvider(_credit_provider);
        collateralManager = ICollateralManager(_collateral_manager);
        settings = ProtocolSettings(_protocol_settings);
        pool = IGovernableLiquidityPool(_pool);
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
        address[] memory tokens = settings.getAllowedTokens();        
        uint[] memory amount = new uint[](1); 
        amount[0] = calcSurplus();

        address[] memory tokenArray = new address[](1); 
        tokenArray[0] = tokens[0];
        //exchange.withdrawTokens(tokenArray, amount);

        (bool success2,) = address(this).call(
            abi.encodePacked(
                exchange.withdrawTokens.selector,
                abi.encode(tokens, amount)
            )
        );
    }
    
    function withdrawTokens(uint amount) public {
        address[] memory tokens = settings.getAllowedTokens();
        uint[] memory amountArray = new uint[](1); 
        amountArray[0] = amount;

        address[] memory tokenArray = new address[](1); 
        tokenArray[0] = tokens[0];
        (bool success2,) = address(this).call(
            abi.encodePacked(
                exchange.withdrawTokens.selector,
                abi.encode(tokenArray, amountArray)
            )
        );


    }

    function writeOption(
        IOptionsExchange.OptionType optType,
        int strike, 
        uint timeTomaturity,
        address pool
    )
        public
        returns (address _tk)
    {
        _tk = writeOptions(1, optType, strike, timeTomaturity, pool);
    }

    function writeOptions(
        uint volume,
        IOptionsExchange.OptionType optType,
        int strike, 
        uint timeToMaturity,
        address pool
    )
        public
        returns (address _tk)
    {

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
        oEi.poolAddrs[0] = pool;//poolAddr;
        //oEi.isCovered[0] = false; //expoliting default to save gas
        //oEi.paymentTokens[0] = address(0); //exploiting default to save gas


        (bool success,) = address(this).call(
            abi.encodePacked(
                exchange.openExposure.selector,
                abi.encode(oEi, address(this))
            )
        );
    }

    function liquidateOptions(address _tk) public {
        
        collateralManager.liquidateOptions(_tk, address(this));
    }

    function transferOptions(address to, address _tk, uint volume) public {

        IOptionToken(_tk).transfer(to, volume * volumeBase);
    }

    function burnOptions(address _tk, uint volume) public {

        IOptionToken(_tk).burn(volume * volumeBase);
    }
    
    function calcCollateral() public view returns (uint) {
        
        return exchange.calcCollateral(addr, true);
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