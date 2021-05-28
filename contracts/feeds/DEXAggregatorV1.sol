pragma solidity >=0.6.0;

import "../interfaces/AggregatorV3Interface.sol";
import '../interfaces/IDEXOracleV1.sol';


contract DEXAggregatorV1 is AggregatorV3Interface {

    mapping(uint => uint) rounds;

    uint latestRound;
    int[] answers;
    uint[] updatedAts;

    addresss _dexOracle;


    constructor(
        address dexOracle,
    )
        public
    {
        _dexOracle = dexOracle;
    }

    function decimals() override external view returns (uint8) {

        return 8;
    }

    function description() override external view returns (string memory) {

    }

    function version() override external view returns (uint256) {

    }

    function appendRoundId(uint rid) external {
        rounds[rid] = answers.length;
        latestRound = rid;
    }

    function appendAnswer() external {
        answers.push(IDEXOracleV1(_dexOracle).latestPrice());
    }

    function appendUpdatedAt(uint ut) external {
        updatedAts.push(IDEXOracleV1(_dexOracle).latestCapture());
    }

    function getRoundData(uint80 _roundId)
        override
        external
        view
        returns
    (
        uint80 roundId,
        int256 answer,
        uint256,
        uint256 updatedAt,
        uint80
    )
    {
        roundId = _roundId;
        answer = answers[rounds[_roundId]];
        updatedAt = updatedAts[rounds[_roundId]];
    }

    function latestRoundId() public view returns (uint) {
        return latestRound;
    }

    function latestRoundData()
        override
        external
        view
        returns
    (
        uint80 roundId,
        int256 answer,
        uint256,
        uint256 updatedAt,
        uint80
    )
    {
        roundId = uint80(latestRound);
        answer = answers[rounds[latestRound]];
        updatedAt = updatedAts[rounds[latestRound]];
    }
}