pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../../contracts/utils/Arrays.sol";
import "../../contracts/utils/ERC20.sol";
import "../../contracts/utils/SafeMath.sol";
import "../../contracts/utils/MoreMath.sol";
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
        uint valRemaining = valTotal;
        uint supplyTotal = _totalSupply;
        uint supplyRemaining = _totalSupply;
        
        for (uint i = 0; i < owners.length; i++) {
            if (owners[i] != address(0)) {
                (uint bal, uint val) = redeem(valTotal, supplyTotal, owners[i]);
                value = value.add(val);
                valRemaining = valRemaining.sub(val);
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
            exchange.transferBalance(owner, val);
            removeBalance(owner, bal);
        }

        afterRedeem(owner, bal, val);
    }

    function withdrawEarly(address owner) external returns (uint value) {        
        uint bal = balanceOf(owner);
        
        if (bal > 0) {
            // burn owners pool tokens, but issue them credit tokens
            uint b = 1e3;
            value = MoreMath.round(
                exchange.balanceOf(
                    address(this)
                ).mul(
                    bal.mul(b)
                ).div(
                    _totalSupply
                ), 
                b
            );
            // this will fail if not called from pool and revert tx
            exchange.processEarlyLpWithdrawal(owner, value);
            removeBalance(owner, bal);
        }
    }

    function afterRedeem(address owner, uint bal, uint val) virtual internal {

    }
}
