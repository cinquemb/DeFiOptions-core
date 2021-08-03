/*
    Copyright 2021 DeFi Options, based on the works of the Empty Set Squad

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinFactory.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinPair.sol";
import "../deployment/Deployer.sol";
import "../utils/PangolinOracleLibrary.sol";
import "../utils/PangolinLibrary.sol";
import "../utils/Decimal.sol";
import "../interfaces/IDEXOracleV1.sol";
import "../interfaces/IProposal.sol";
import "../interfaces/IProtocolSettings.sol";

contract DEXOracleV1 is IDEXOracleV1 {
    using Decimal for Decimal.D256;

    address internal _pairAddr;
    address internal _exchange;
    address internal _settings;
    address internal _underlying;
    address internal _stablecoin;

    uint256 private serial;
    uint256 internal _index;
    uint256 internal _reserve;
    uint256 internal _cumulative;
    uint256 internal _lastCapture;
    uint256 internal _twapPeriodMax = 60 * 60 * 24; // 1 day
    uint256 internal _twapPeriod = 60 * 60 * 24; // 1 day
    uint256 internal _twapPeriodMin = 60 * 60 * 2; // 2 hours

    bool private _latestValid;
    bool internal _initialized;

    uint32 internal _timestamp;
    int256 private _latestPrice;

    IPangolinPair internal _pair;

    mapping(address => uint) private proposingId;
    mapping(uint => address) private proposalsMap;

    constructor (address _deployAddr, address underlying, address stable, address dexTokenPair) public {

        Deployer deployer = Deployer(_deployAddr);

        _exchange = deployer.getContractAddress("OptionsExchange");
        _settings = deployer.getContractAddress("ProtocolSettings");
        _underlying = underlying;
        _stablecoin = stable;
        _pairAddr = dexTokenPair;

        (uint r, uint b) = IProtocolSettings(_settings).getTokenRate(_stablecoin);
        require(r != 0 && b != 0, "DEXOracleV1: token not allowed");
        
        _pair = IPangolinPair(_pairAddr);
        (address token0, address token1) = (_pair.token0(), _pair.token1());
        _index = _underlying == token0 ? 0 : 1;
        require(_index == 0 || _underlying == token1, "DEXOracleV1: Underlying not found");
    }

    /**
     * Trades/Liquidity: (1) Initializes reserve and blockTimestampLast (can calculate a price)
     *                   (2) Has non-zero cumulative prices
     *
     * Steps: (1) Captures a reference blockTimestampLast
     *        (2) First reported value
     */
    function capture() override public onlyExchange returns (int256, bool) {
        uint256 currentTime = IProtocolSettings(_settings).exchangeTime();

        if (_lastCapture != 0) {
            require(SafeMath.sub(currentTime, _lastCapture) >= _twapPeriod, "DEXOracleV1: too soon");
        }

        if (_initialized) {
            _lastCapture = currentTime;
            return updateOracle();
        } else {
            initializeOracle();
            _lastCapture = currentTime;
            return updateOracle();
        }
    }

    function initializeOracle() private {
        IPangolinPair pair = _pair;
        uint256 priceCumulative = _index == 0 ?
            pair.price0CumulativeLast() :
            pair.price1CumulativeLast();
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair.getReserves();
        if(reserve0 != 0 && reserve1 != 0 && blockTimestampLast != 0) {
            _cumulative = priceCumulative;
            _timestamp = blockTimestampLast;
            _initialized = true;
            _reserve = _index == 0 ? reserve1 : reserve0; // get counter's reserve
        }
    }

    function updateOracle() private returns (int256, bool) {
        int256 price = updatePrice();
        updateReserve();

        bool valid = true;

        if (price < 1e8) {
            valid = false;
        }

        _latestValid = valid;
        _latestPrice = price;

        return (price, valid);
    }

    function updatePrice() private returns (int256) {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
        PangolinOracleLibrary.currentCumulativePrices(address(_pair));
        uint32 timeElapsed = blockTimestamp - _timestamp; // overflow is desired
        uint256 priceCumulative = _index == 0 ? price0Cumulative : price1Cumulative;
        Decimal.D256 memory price = Decimal.ratio((priceCumulative - _cumulative) / timeElapsed, 2**112);

        _timestamp = blockTimestamp;
        _cumulative = priceCumulative;

        return int256(price.mul(1e8).asUint256());
    }

    function updateReserve() private returns (uint256) {
        uint256 lastReserve = _reserve;
        (uint112 reserve0, uint112 reserve1,) = _pair.getReserves();
        _reserve = _index == 0 ? reserve1 : reserve0; // get counter's reserve

        return lastReserve;
    }

    function liveReserve() override external view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = _pair.getReserves();
        uint256 lastReserve = _index == 0 ? reserve1 : reserve0; // get counter's reserve

        return lastReserve;
    }

    function updateTwapPeriod(uint256 twapPeriod) override external onlyGovernance {
        require((_twapPeriod >= _twapPeriodMin) && (_twapPeriod <= _twapPeriodMax), "DEXOracleV1: outside of twap bounds");

        _twapPeriod = twapPeriod;
    }

    function registerProposal(address addr) override external returns (uint id) {
        require(
            proposingId[addr] == 0,
            "already proposed"
        );

        id = serial++;
        IProposal(addr).open(id);
        proposalsMap[id] = addr;
        proposingId[addr] = id;
    }

    function proposalCount() override external view returns (uint) {
        return serial;
    }

    function proposalAddr(uint id) override external view returns (address) {
        return proposalsMap[id];
    }

    function stablecoin() internal view returns (address) {
        return _stablecoin;
    }

    function pair() override external view returns (address) {
        return _pairAddr;
    }

    function latestPrice() override public view returns (int256) {
        return _latestPrice;
    }

    function latestValid() override public view returns (bool) {
        return _latestValid;
    }

    function latestCapture() override public view returns (uint256) {
        return _lastCapture;
    }

    modifier onlyGovernance() {
        IProposal p = IProposal(msg.sender);
        require(proposalsMap[p.getId()] == msg.sender && p.isOracleSettingsAllowed(), "DEXOracleV1: proposal not registered or not allowed");
        _;
    }

    modifier onlyExchange() {
        require(msg.sender == _exchange, "DEXOracleV1: Not exchange");

        _;
    }
}