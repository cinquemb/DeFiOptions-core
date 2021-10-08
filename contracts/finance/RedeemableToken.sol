pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../utils/Arrays.sol";
import "../utils/ERC20.sol";
import "../utils/MoreMath.sol";
import "../interfaces/IOptionsExchange.sol";

abstract contract RedeemableToken is ERC20 {

    using SafeMath for uint;

    IOptionsExchange internal exchange;

    function redeemAllowed() virtual public view returns(bool);

    function redeem(address owner) external returns (uint value) {

        address[] memory owners = new address[](1);
        owners[0] = owner;
        value = redeem(owners);
    }

    function redeem(address[] memory owners) public returns (uint value) {

        require(redeemAllowed(), "redeemd not allowed");

        uint valTotal = exchange.balanceOf(address(this));
        uint supplyTotal = _totalSupply;
        uint supplyRemaining = _totalSupply;
        
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] != address(0)) {
                (uint bal, uint val) = redeem(valTotal, supplyTotal, owners[i]);
                value = value.add(val);
                supplyRemaining = supplyRemaining.sub(bal);
            }
        }

        _totalSupply = supplyRemaining;
    }

    function redeem(uint valTotal, uint supplyTotal, address owner) 
        private
        returns (uint bal, uint val)
    {
        bal = balanceOf(owner);
        
        if (bal > 0) {
            uint b = 1e3;
            val = MoreMath.round(valTotal.mul(bal.mul(b)).div(supplyTotal), b);
            removeBalance(owner, bal);
            exchange.transferBalance(owner, val);
        }

        afterRedeem(owner, bal, val);
    }

    function afterRedeem(address owner, uint bal, uint val) virtual internal {

    }
}
