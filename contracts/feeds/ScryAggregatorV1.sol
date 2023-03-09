pragma solidity >=0.6.0;

import "../interfaces/AggregatorV3Interface.sol";
import "../interfaces/IScryOpenOracleFramework.sol";


contract ScryAggregatorV1 is AggregatorV3Interface {

    mapping(uint => uint) rounds;

    uint latestRound;
    int[] answers;
    uint[] updatedAts;

    bool private lockedRound = true;
    bool private lockedAnswers = true;
    bool private lockedUpdatedAts = true;

    address _scryOracleAddr;
    uint _feedId;


    constructor(address scryOracleAddr, uint feedId) public {
        _scryOracleAddr = scryOracleAddr;
        _feedId = feedId;
    }

    function decimals() override external view returns (uint8) {
        (,, uint256 feedDecimals) = IScryOpenOracleFramework(_scryOracleAddr).getFeed(_feedId);

        return uint8(feedDecimals);
    }

    function description() override external view returns (string memory) {

    }

    function version() override external view returns (uint256) {

    }

    /* SEEDING FOR INITIALIZATION BELOW */

    function setRoundIds(uint[] calldata rids) external {
        require(lockedRound == false && latestRound == 0, "already init round");
        for (uint i = 0; i < rids.length; i++) {
            rounds[rids[i]] = i;
        }

        latestRound = rids[ rids.length - 1];
        lockedRound = true;
    }

    function setAnswers(int[] calldata ans) external {
        require(lockedAnswers == false && answers.length == 0, "already init answers");
        answers = ans;
        lockedAnswers = true;
    }

    function setUpdatedAts(uint[] calldata uts) external {
        require(lockedUpdatedAts == false && updatedAts.length == 0, "already init answers");
        updatedAts = uts;
        lockedUpdatedAts = true;
    }

    /* SEEDING FOR INITIALIZATION ABOVE */

    function oracle() external view returns (address) {
        return _scryOracleAddr;
    }

    function incrementRound() external {
        appendUpdatedAt();
        appendAnswer();
        appendRoundId();
    }

    function appendRoundId() private {
        if (answers.length > 1) {
            rounds[latestRound++] = answers.length;
        } else {
            rounds[latestRound] = answers.length;
        }
    }

    function appendAnswer() private {
        (uint256 feedValueRAW,,) = IScryOpenOracleFramework(_scryOracleAddr).getFeed(_feedId);
        answers.push(int256(feedValueRAW));
    }

    function appendUpdatedAt() private {
        (, uint256 feedLastTimeStamp,) = IScryOpenOracleFramework(_scryOracleAddr).getFeed(_feedId);
        updatedAts.push(feedLastTimeStamp);
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

        (uint256 feedValueRAW, uint256 feedLastTimeStamp,) = IScryOpenOracleFramework(_scryOracleAddr).getFeed(_feedId);

        roundId = uint80(latestRound);
        answer = int256(feedValueRAW);
        updatedAt = feedLastTimeStamp;
    }
}