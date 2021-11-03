pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../interfaces/IProtocolSettings.sol";
import "../interfaces/IERC20.sol";


abstract contract Proposal {

    function getName() public virtual view returns (string memory);

    function execute(IProtocolSettings _settings) public virtual;

    function executePool(IERC20 _llp) public virtual;
}