pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";

contract MetavalutHedgingManager is BaseHedgingManager {
	address public positionManager;
	address public reader;
}