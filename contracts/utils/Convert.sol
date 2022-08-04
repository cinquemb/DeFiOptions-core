pragma solidity >=0.6.0;

import "../interfaces/IERC20Details.sol";
import "../utils/MoreMath.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";

library Convert {

    using SafeMath for uint;
    using SignedSafeMath for int;

    function to18DecimalsBase(address tk, uint value) internal view returns(uint) {

        uint b1 = 18;
        uint b2 = IERC20Details(tk).decimals();
        return formatValue(value, b1, b2);
    }

    function from18DecimalsBase(address tk, uint value) internal view returns(uint) {

        uint b1 = 18;
        uint b2 = IERC20Details(tk).decimals();
        return formatValue(value, b2, b1);
    }

    function formatValue(uint value, uint b1, uint b2) internal pure returns(uint) {
        
        if (b2 < b1) {
            value = value.mul(MoreMath.pow(10, (b1.sub(b2))));
        }
        
        if (b2 > b1) {
            value = value.div(MoreMath.pow(10, (b2.sub(b1))));
        }

        return value;
    }

    function formatValue(int value, int b1, int b2) internal pure returns(int) {
        
        if (b2 < b1) {
            value = value.mul(int256(MoreMath.pow(10, uint256(b1.sub(b2)))));
        }
        
        if (b2 > b1) {
            value = value.div(int256(MoreMath.pow(10, uint256(b2.sub(b1)))));
        }

        return value;
    }
}