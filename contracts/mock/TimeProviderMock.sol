pragma solidity >=0.6.0;

import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../interfaces/TimeProvider.sol";

contract TimeProviderMock is TimeProvider, ManagedContract {
    
    uint offset = 0;
    int fixedTime = -1;
    
    constructor(address deployer) public {

        Deployer(deployer).setContractAddress("TimeProvider");
    }
    
    function getNow() override external view returns (uint) {
        return fixedTime >= 0 ? uint(fixedTime) : block.timestamp + offset;
    }
    
    function setTimeOffset(uint _offset) public {
        offset = _offset;
        fixedTime = -1;
    }

    function setFixedTime(int _fixedTime) public {
        fixedTime = _fixedTime;
    }
}