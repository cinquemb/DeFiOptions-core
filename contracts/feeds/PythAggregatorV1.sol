pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../interfaces/AggregatorV3Interface.sol";
import "../interfaces/external/pyth/IPyth.sol";
import "../utils/MoreMath.sol";


contract PythAggregatorV1 is AggregatorV3Interface {

    mapping(uint => uint) rounds;

    uint latestRound;
    int[] answers;
    uint[] updatedAts;

    bool private lockedRound = true;
    bool private lockedAnswers = true;
    bool private lockedUpdatedAts = true;

    address _pythOracleAddr;
    bytes32 _feedId;


    constructor(address pythOracleAddr, bytes32 feedId) public {

        /*
            oracle addrs: https://docs.pyth.network/pythnet-price-feeds/evm
            
            Goerli (Ethereum testnet) 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C
            Fuji (Avalanche testnet) 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C
            Fantom testnet 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C
            Mumbai (Polygon testnet) 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C

            feed ids: https://pyth.network/developers/price-feed-ids

            MAINET

            btc/usd: 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43
            eth/usd: 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
            matic/usd: 0x5de33a9112c2b700b8d30b8a3402c103578ccfa2765696471cc672bd5cf6ac52
            avax/usd: 0x93da3352f9f1d105fdfe4971cfa80e9dd777bfc5d0f683ebb6e1294b92137bb7

            TESTNET

            btc/usd: 0xf9c0172ba10dfa4d19088d94f5bf61d3b54d5bd7483a322a982e1373ee8ea31b
            eth/usd: 0xca80ba6dc32e08d06f1aa886011eed1d77c77be9eb761cc10d72b7d0a2fd57a6
            matic/usd: 0xd2c2c1f2bba8e0964f9589e060c2ee97f5e19057267ac3284caef3bd50bd2cb5
            avax/usd: 0xd7566a3ba7f7286ed54f4ae7e983f4420ae0b1e0f3892e11f9c4ab107bbad7b9

        */
        _pythOracleAddr = pythOracleAddr;
        _feedId = feedId;
    }

    function decimals() override external view returns (uint8) {
        IPyth.Price memory p = IPyth(_pythOracleAddr).getPriceUnsafe(_feedId);
        return uint8(MoreMath.abs(p.expo));
    }

    function description() override external view returns (string memory) {
        return bytes32ToString(_feedId);
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
        return _pythOracleAddr;
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
        IPyth.Price memory p = IPyth(_pythOracleAddr).getPriceUnsafe(_feedId);
        answers.push(p.price);
    }

    function appendUpdatedAt() private {
        IPyth.Price memory p = IPyth(_pythOracleAddr).getPriceUnsafe(_feedId);
        updatedAts.push(uint(p.publishTime));
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
        IPyth.Price memory p = IPyth(_pythOracleAddr).getPriceUnsafe(_feedId);

        roundId = uint80(latestRound);
        answer = p.price;
        updatedAt = uint(p.publishTime);
    }

    function bytes32ToString(bytes32 x) private pure returns (string) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }
}