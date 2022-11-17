pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/IProtocolSettings.sol";
import "../interfaces/ICreditProvider.sol";
import "../interfaces/IBaseCollateralManager.sol";
import "../interfaces/UnderlyingFeed.sol";
import "../interfaces/IOptionsExchange.sol";
import "../feeds/DEXAggregatorV1.sol";


contract Incentivized is ManagedContract {
	
	IProtocolSettings private settings;
    ICreditProvider private creditProvider;
    IBaseCollateralManager private collateralManager;
    IOptionsExchange private exchange;

    event IncentiveReward(address indexed from, uint value);

	function initialize(Deployer deployer) override internal {
        creditProvider = ICreditProvider(deployer.getContractAddress("CreditProvider"));
        settings = IProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        collateralManager = IBaseCollateralManager(deployer.getContractAddress("CollateralManager"));
        exchange = IOptionsExchange(deployer.getContractAddress("OptionsExchange"));
    }

    function incrementRoundDexAgg(address dexAggAddr) external {
        // this is needed to provide data for UnderlyingFeed that originate from a dex
        //require(settings.checkDexAggIncentiveBlacklist(dexAggAddr) == false, "blacklisted for incentives");
        DEXAggregatorV1(dexAggAddr).incrementRound();
    }

    function prefetchSample(address udlFeed) incentivized external {
        require(settings.checkUdlIncentiveBlacklist(udlFeed) == false, "blacklisted for incentives");
        require(settings.getUdlFeed(udlFeed) > 0, "feed not allowed");
        UnderlyingFeed(udlFeed).prefetchSample();
    }

    function prefetchDailyPrice(address udlFeed, uint roundId) incentivized external {
        require(settings.checkUdlIncentiveBlacklist(udlFeed) == false, "blacklisted for incentives");
        require(settings.getUdlFeed(udlFeed) > 0, "feed not allowed");
        UnderlyingFeed(udlFeed).prefetchDailyPrice(roundId);
    }

    function prefetchDailyVolatility(address udlFeed, uint timespan) incentivized external {
        require(settings.checkUdlIncentiveBlacklist(udlFeed) == false, "blacklisted for incentives");
        require(settings.getUdlFeed(udlFeed) > 0, "feed not allowed");
        require(settings.getVolatilityPeriod() == timespan, "non gov timespan");
        (uint vol, bool cached) = UnderlyingFeed(udlFeed).getDailyVolatilityCached(timespan);
        require(cached != true, "already fetched vol");
        UnderlyingFeed(udlFeed).prefetchDailyVolatility(timespan);
    }

    function liquidateExpired(address _tk, address[] calldata owners) external {
        IBaseCollateralManager(
            settings.getUdlCollateralManager(exchange.getOptionData(_tk).udlFeed)
        ).liquidateExpired(_tk, owners);
    }

    function liquidateOptions(address _tk, address owner) public returns (uint value) {
        value = IBaseCollateralManager(
            settings.getUdlCollateralManager(exchange.getOptionData(_tk).udlFeed)
        ).liquidateOptions(_tk, owner);
    }

    modifier incentivized() {
        //uint256 startGas = gasleft();

        _;
        
        //uint256 gasUsed = startGas - gasleft();
        address[] memory tokens = settings.getAllowedTokens();

        uint256 creditingValue = settings.getBaseIncentivisation();        
        creditProvider.processIncentivizationPayment(msg.sender, creditingValue);
        emit IncentiveReward(msg.sender, creditingValue);    
    }
}