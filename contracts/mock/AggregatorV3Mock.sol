pragma solidity >=0.6.0;

import "../interfaces/AggregatorV3Interface.sol";

contract AggregatorV3Mock is AggregatorV3Interface {

    mapping(uint => uint) rounds;

    uint latestRound;
    int[] answers;
    uint[] updatedAts;

    function decimals() override external view returns (uint8) {

        return 8;
    }

    function description() override external view returns (string memory) {

    }

    function version() override external view returns (uint256) {

    }

    function setRoundIds(uint[] calldata rids) external {
        for (uint i = 0; i < rids.length; i++) {
            rounds[rids[i]] = i;
        }

        latestRound = rids[ rids.length - 1];
    }

    function appendRoundId(uint rid) external {
        rounds[rid] = answers.length;
        latestRound = rid;
    }

    function setAnswers(int[] calldata ans) external {
        answers = ans;
    }

    function appendAnswer(int ans) external {
        answers.push(ans);
    }

    function setUpdatedAts(uint[] calldata uts) external {
        updatedAts = uts;
    }

    function appendUpdatedAt(uint ut) external {
        updatedAts.push(ut);
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