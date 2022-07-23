pragma solidity >=0.6.0;

import "./SafeMath.sol";
import "./SignedSafeMath.sol";

library MoreMath {

    using SafeMath for uint;
    using SignedSafeMath for int;


    //see: https://ethereum.stackexchange.com/questions/8086/logarithm-math-operation-in-solidity
    /**
     * 2^127.
     */
    uint128 private constant TWO127 = 0x80000000000000000000000000000000;

    /**
     * 2^128 - 1.
     */
    uint128 private constant TWO128_1 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    /**
     * ln(2) * 2^128.
     */
    uint128 private constant LN2 = 0xb17217f7d1cf79abc9e3b39803f2f6af;

    /**
     * Return index of most significant non-zero bit in given non-zero 256-bit
     * unsigned integer value.
     *
     * @param x value to get index of most significant non-zero bit in
     * @return index of most significant non-zero bit in given number
     */
    function mostSignificantBit (uint256 x) pure internal returns (uint8 r) {
      // for high-precision ln(x) implementation for 128.128 fixed point numbers
      require (x > 0);

      if (x >= 0x100000000000000000000000000000000) {x >>= 128; r += 128;}
      if (x >= 0x10000000000000000) {x >>= 64; r += 64;}
      if (x >= 0x100000000) {x >>= 32; r += 32;}
      if (x >= 0x10000) {x >>= 16; r += 16;}
      if (x >= 0x100) {x >>= 8; r += 8;}
      if (x >= 0x10) {x >>= 4; r += 4;}
      if (x >= 0x4) {x >>= 2; r += 2;}
      if (x >= 0x2) r += 1; // No need to shift x anymore
    }
    /*
    function mostSignificantBit (uint256 x) pure internal returns (uint8) {
      // for high-precision ln(x) implementation for 128.128 fixed point numbers
      require (x > 0);

      uint8 l = 0;
      uint8 h = 255;

      while (h > l) {
        uint8 m = uint8 ((uint16 (l) + uint16 (h)) >> 1);
        uint256 t = x >> m;
        if (t == 0) h = m - 1;
        else if (t > 1) l = m + 1;
        else return m;
      }

      return h;
    }
    */

    /**
     * Calculate log_2 (x / 2^128) * 2^128.
     *
     * @param x parameter value
     * @return log_2 (x / 2^128) * 2^128
     */
    function log_2 (uint256 x) pure internal returns (int256) {
      // for high-precision ln(x) implementation for 128.128 fixed point numbers
      require (x > 0);

      uint8 msb = mostSignificantBit (x);

      if (msb > 128) x >>= msb - 128;
      else if (msb < 128) x <<= 128 - msb;

      x &= TWO128_1;

      int256 result = (int256 (msb) - 128) << 128; // Integer part of log_2

      int256 bit = TWO127;
      for (uint8 i = 0; i < 128 && x > 0; i++) {
        x = (x << 1) + ((x * x + TWO127) >> 128);
        if (x > TWO128_1) {
          result |= bit;
          x = (x >> 1) - TWO127;
        }
        bit >>= 1;
      }

      return result;
    }

    /**
     * Calculate ln (x / 2^128) * 2^128.
     *
     * @param x parameter value
     * @return ln (x / 2^128) * 2^128
     */
    function ln (uint256 x) pure internal returns (int256) {
      // for high-precision ln(x) implementation for 128.128 fixed point numbers
      require (x > 0);

      int256 l2 = log_2 (x);
      if (l2 == 0) return 0;
      else {
        uint256 al2 = uint256 (l2 > 0 ? l2 : -l2);
        uint8 msb = mostSignificantBit (al2);
        if (msb > 127) al2 >>= msb - 127;
        al2 = (al2 * LN2 + TWO127) >> 128;
        if (msb > 127) al2 <<= msb - 127;

        return int256 (l2 >= 0 ? al2 : -al2);
      }
    }

    // rounds "v" considering a base "b"
    function round(uint v, uint b) internal pure returns (uint) {

        return v.div(b).add((v % b) >= b.div(2) ? 1 : 0);
    }

    // calculates {[(n/d)^e]*f}
    function powAndMultiply(uint n, uint d, uint e, uint f) internal pure returns (uint) {
        
        if (e == 0) {
            return 1;
        } else if (e == 1) {
            return f.mul(n).div(d);
        } else {
            uint p = powAndMultiply(n, d, e.div(2), f);
            p = p.mul(p).div(f);
            if (e.mod(2) == 1) {
                p = p.mul(n).div(d);
            }
            return p;
        }
    }

    // calculates (n^e)
    function pow(uint n, uint e) internal pure returns (uint) {
        
        if (e == 0) {
            return 1;
        } else if (e == 1) {
            return n;
        } else {
            uint p = pow(n, e.div(2));
            p = p.mul(p);
            if (e.mod(2) == 1) {
                p = p.mul(n);
            }
            return p;
        }
    }

    // calculates {n^(e/b)}
    function powDecimal(uint n, uint e, uint b) internal pure returns (uint v) {
        
        if (e == 0) {
            return b;
        }

        if (e > b) {
            return n.mul(powDecimal(n, e.sub(b), b)).div(b);
        }

        v = b;
        uint f = b;
        uint aux = 0;
        uint rootN = n;
        uint rootB = sqrt(b);
        while (f > 1) {
            f = f.div(2);
            rootN = sqrt(rootN).mul(rootB);
            if (aux.add(f) < e) {
                aux = aux.add(f);
                v = v.mul(rootN).div(b);
            }
        }
    }
    
    // calculates ceil(n/d)
    function divCeil(uint n, uint d) internal pure returns (uint v) {
        
        v = n.div(d);
        if (n.mod(d) > 0) {
            v = v.add(1);
        }
    }
    
    // calculates the square root of "x" and multiplies it by "f"
    function sqrtAndMultiply(uint x, uint f) internal pure returns (uint y) {
    
        y = sqrt(x.mul(1e18)).mul(f).div(1e9);
    }
    
    // calculates the square root of "x"
    function sqrt(uint x) internal pure returns (uint y) {
    
        uint z = (x.div(2)).add(1);
        y = x;
        while (z < y) {
            y = z;
            z = (x.div(z).add(z)).div(2);
        }
    }

    // calculates the standard deviation
    function std(int[] memory array) internal pure returns (uint _std) {

        int avg = sum(array).div(int(array.length));
        uint x2 = 0;
        for (uint i = 0; i < array.length; i++) {
            int p = array[i].sub(avg);
            x2 = x2.add(uint(p.mul(p)));
        }
        _std = sqrt(x2 / array.length);
    }

    function sum(int[] memory array) internal pure returns (int _sum) {

        for (uint i = 0; i < array.length; i++) {
            _sum = _sum.add(array[i]);
        }
    }

    function abs(int a) internal pure returns (uint) {

        return uint(a < 0 ? -a : a);
    }
    
    function max(int a, int b) internal pure returns (int) {
        
        return a > b ? a : b;
    }
    
    function max(uint a, uint b) internal pure returns (uint) {
        
        return a > b ? a : b;
    }
    
    function min(int a, int b) internal pure returns (int) {
        
        return a < b ? a : b;
    }
    
    function min(uint a, uint b) internal pure returns (uint) {
        
        return a < b ? a : b;
    }

    function toString(uint v) internal pure returns (string memory str) {

        str = toString(v, true);
    }
    
    function toString(uint v, bool scientific) internal pure returns (string memory str) {

        if (v == 0) {
            return "0";
        }

        uint maxlength = 100;
        bytes memory reversed = new bytes(maxlength);
        uint i = 0;
        
        while (v != 0) {
            uint remainder = v % 10;
            v = v / 10;
            reversed[i++] = byte(uint8(48 + remainder));
        }

        uint zeros = 0;
        if (scientific) {
            for (uint k = 0; k < i; k++) {
                if (reversed[k] == '0') {
                    zeros++;
                } else {
                    break;
                }
            }
        }

        uint len = i - (zeros > 2 ? zeros : 0);
        bytes memory s = new bytes(len);
        for (uint j = 0; j < len; j++) {
            s[j] = reversed[i - j - 1];
        }

        str = string(s);

        if (scientific && zeros > 2) {
            str = string(abi.encodePacked(s, "e", toString(zeros, false)));
        }
    }
}