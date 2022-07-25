pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "./BaseHedgingManager.sol";
import "../interfaces/ICollateralManager.sol";
import "../interfaces/external/metavault/IPositionManager.sol";
import "../interfaces/external/metavault/IReader.sol";

contract MetavalutHedgingManager is BaseHedgingManager {
	address public positionManagerAddr;
	address public readerAddr;

	function initialize(Deployer deployer, address _positionManager, address _reader) override internal {
        super.initialize(deployer);
        positionManagerAddr = _positionManager;
        readerAddr = _reader;
    }

	/*
		USD values for _sizeDelta and _price are multiplied by (10 ** 30), so for example to open a long position of size 1000 USD, the value 1000 * (10 ** 30) should be used 

		need to convert from 10 ** 18 and back when appropriate

	*/

	function getHedgeExposure(address underlying, address account) override public view returns (uint) {
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
    
    function idealHedgeExposure(address underlying, address account) override public view returns (int256) {
    	// look at order book for account and compute the delta for the given underlying
    	(,address[] memory _tokens, uint[] memory _holding,, uint[] memory _uncovered, int[] memory _iv) = exchange.getBook(owner);

    	//ICollateralManager(settings.getUdlCollateralManager(opt.udlFeed));

    }
    
    function realHedgeExposure(address underlying, address account) override public view returns (int256) {
    	// look at metavault exposure for underlying, and divide by asset price

    }
    
    function balanceExposure(address underlying, address account) override external returns (bool) {
    	//TODO: CAN ONLY DO THIS EVERY 15 MIN WITH METAVAULT? But up to them to enforce it?
    	//options trades should trigger this

    	int256 ideal = idealHedgeExposure(underlying, account);
    	int256 real = realHedgeExposure(underlying, account);
    	int256 diff = ideal - real;

    	/*
	    	- FOR increasePosition
	    	- _sizeDelta is 0 for adding collateral with non zero _amountIn
	    	- pool needs to have permision to sends funds from their exchange balance to perp protocol
	    */

	    /*
	   		FOR decreasePositionAndSwap
		    - set _collateralDelta to the amount the exchagne wants to withdraw from perp protocol
		    - _receiver address needs to be withdrawn to the credit provider address in the acceabtle stablecoins
		    	- liquidty pool needs to be credited with the amount recieved
		*/

    	if (ideal >= 0) {
    		uint256 pos_size = uint256(abs(diff));
    		if (real < 0) {
    			//need to close short position first
    			IPositionManager(positionManagerAddr).decreasePositionAndSwap(
			        address[] memory _path,
			        underlying,//address _indexToken,
			        uint256 _collateralDelta,
			        uint256 _sizeDelta,
			        false,//bool _isLong,
			        address _receiver,
			        uint256 _price,
			        uint256 _minOut
			    );

			    pos_size = uint256(ideal);
    		}
    		
    		// increase long position by pos_size
    		if (pos_size != 0) {
    			IPositionManager(positionManagerAddr).increasePosition(
			        address[] memory _path,
			        underlying,//address _indexToken,
			        uint256 _amountIn,
			        uint256 _minOut,
			        uint256 _sizeDelta,
			        true,// bool _isLong
			        uint256 _price
			    );
    		}
    	} else if (ideal < 0) {
    		uint256 pos_size = uint256(abs(diff));
			if (real > 0) {
				// need to close long position first
				IPositionManager(positionManagerAddr).decreasePositionAndSwap(
			        address[] memory _path,
			        underlying,//address _indexToken,
			        uint256 _collateralDelta,
			        uint256 _sizeDelta,
			        true, //bool _isLong,
			        address _receiver,
			        uint256 _price,
			        uint256 _minOut
			    );

			    pos_size = uint256(abs(ideal));
			}

			// increase short position by pos_size
			if (pos_size != 0) {
    			IPositionManager(positionManagerAddr).increasePosition(
			        address[] memory _path,
			        underlying,//address _indexToken,
			        uint256 _amountIn,
			        uint256 _minOut,
			        uint256 _sizeDelta,
			        false, //bool _isLong,
			        uint256 _price
			    );
    		}
		}
    } 
}