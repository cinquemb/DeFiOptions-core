pragma solidity >=0.6.0;

import "truffle/Assert.sol";
//import "truffle/DeployedAddresses.sol";
import "../../../contracts/feeds/ChainlinkFeed.sol";
import "../../common/mock/AggregatorV3Mock.t.sol";
import "../../common/mock/ERC20Mock.t.sol";
import "../../common/mock/EthFeedMock.t.sol";
import "../../common/mock/TimeProviderMock.t.sol";
import "../../common/mock/UniswapV2RouterMock.t.sol";

abstract contract Base {

    ChainlinkFeed feed;
    TimeProviderMock time;
    
    uint[] roundIds;
    int[] answers;
    int[] prices;
    uint[] updatedAts;
    
    int price;
    bool cached;

    //function beforeEachDeploy() public {
    function setUp() public {

        time = new TimeProviderMock();

        roundIds = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
        answers = [20e8, 25e8, 28e8, 18e8, 19e8, 12e8, 12e8, 13e8, 18e8, 20e8];
        prices = [20e18, 25e18, 28e18, 18e18, 19e18, 12e18, 12e18, 13e18, 18e18, 20e18];
        updatedAts = 
            [1 days, 2 days, 3 days, 4 days, 5 days, 6 days, 7 days, 8 days, 9 days, 10 days];

        AggregatorV3Mock mock = new AggregatorV3Mock(roundIds, answers, updatedAts);

        feed = new ChainlinkFeed(
            "ETH/USD",
            address(0),
            address(0),
            address(mock), 
            address(time),
            0, 
            new uint[](0), 
            new int[](0)
        );
        
        time.setFixedTime(10 days);
    }
}