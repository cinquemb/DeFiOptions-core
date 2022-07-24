pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";
import "..interfaces/external/metavault/IPositionManager.sol";
import "..interfaces/external/metavault/IReader.sol";

contract MetavalutHedgingManager is BaseHedgingManager {
	address public positionManagerAddr;
	address public readerAddr;

	function initialize(Deployer deployer, address _positionManager, address _reader) override internal {
        super.initialize(deployer);
        positionManagerAddr = _positionManager;
        readerAddr = _reader;
    }

	//USD values for _sizeDelta and _price are multiplied by (10 ** 30), so for example to open a long position of size 1000 USD, the value 1000 * (10 ** 30) should be used

	function getHedgeExposure(address underlying, address account) public view returns (uint) {
		address[] memory allowedTokens = settings.getAllowedTokens();
		address[] memory _collateralTokens = new address[](allowedTokens.length * 2);
		address[] memory _indexTokens = new address[](allowedTokens.length * 2);
		bool[] memory _isLong = new bool[](allowedTokens.length * 2);

		for (uint i=0; i<allowedTokens.length; i++) {
			
			_collateralTokens.push(allowedTokens[i]);
			_collateralTokens.push(allowedTokens[i]);
			
			_indexTokens.push(underlying);
			_indexTokens.push(underlying);
			
			_isLong.push(true);
			_isLong.push(false);
		}

		uint256[] memory posData = IReader(reader).getPositions(
			IPositionManager(positionManagerAddr).vault(),
			account,
			_collateralTokens, //need to be the approved stablecoins on dod * [long, short]
			address[] memory _indexTokens,
			bool[] memory _isLong
		);
	}
    function idealHedgeExposure(address underlying) virtual internal view returns (uint);
    function realHedgeExposure(address underlying) virtual internal view returns (uint);
    function balanceExposure(address underlying) virtual internal returns (bool); //TODO: CAN ONLY DO THIS EVERY 15 MIN WITH METAVAULT
}