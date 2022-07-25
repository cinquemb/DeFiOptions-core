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

    function cumulativeDistributionFunction(int256 x) internal pure returns (int256) {
        /* inspired by https://github.com/Alexangelj/option-elasticity/blob/8dc10b9555c2b7885423c05c4a49e5bcf53a172b/contracts/libraries/Pricing.sol */

        // where p = 0.3275911,
        // a1 = 0.254829592, a2 = −0.284496736, a3 = 1.421413741, a4 = −1.453152027, a5 = 1.061405429
        // using 18 decimals
        int256 p = 3275911e11;//0x53dd02a4f5ee2e46;
        int256 one = 1e18;//ABDKMath64x64.fromUInt(1);
        int256 two = 2e18;//ABDKMath64x64.fromUInt(2);
        int256 a3 = 1421413741e9;//0x16a09e667f3bcc908;
        int256 z = x.div(a3);
        int256 t = one.div(one.add(p.mul(z.abs())));
        int256 erf = getErrorFunction(z, t);
        if (z < 0) {
            erf = one.sub(erf);
        }
        int256 result = (one.div(two)).mul(one.add(erf));
        return result;
    }

    function getErrorFunction(int256 z, int256 t) internal pure returns (int256) {
        /* inspired by https://github.com/Alexangelj/option-elasticity/blob/8dc10b9555c2b7885423c05c4a49e5bcf53a172b/contracts/libraries/Pricing.sol */

        // where a1 = 0.254829592, a2 = −0.284496736, a3 = 1.421413741, a4 = −1.453152027, a5 = 1.061405429
        // using 18 decimals
        int256 step1;
        {
            int256 a3 = 1421413741e9;//0x16a09e667f3bcc908;
            int256 a4 = -1453152027e9;//-0x17401c57014c38f14;
            int256 a5 = 1061405429e9;//0x10fb844255a12d72e;
            step1 = t.mul(a3.add(t.mul(a4.add(t.mul(a5)))));
        }

        int256 result;
        {
            int256 one = 1e18;//ABDKMath64x64.fromUInt(1);
            int256 a1 = 254829592e9;//0x413c831bb169f874;
            int256 a2 = -284496736e9;//-0x48d4c730f051a5fe;
            int256 step2 = a1.add(t.mul(a2.add(step1)));
            result = one.sub(
                t.mul(
                    step2.mul(
                        int256(optimalExp(one.sub((z).pow(2))))
                    )
                )
            );
        }
        return result;
    }

    /**
      * @dev computes e ^ (x / FIXED_1) * FIXED_1
      * input range: 0 <= x <= OPT_EXP_MAX_VAL - 1
      * auto-generated via 'PrintFunctionOptimalExp.py'
      * Detailed description:
      * - Rewrite the input as a sum of binary exponents and a single residual r, as small as possible
      * - The exponentiation of each binary exponent is given (pre-calculated)
      * - The exponentiation of r is calculated via Taylor series for e^x, where x = r
      * - The exponentiation of the input is calculated by multiplying the intermediate results above
      * - For example: e^5.521692859 = e^(4 + 1 + 0.5 + 0.021692859) = e^4 * e^1 * e^0.5 * e^0.021692859
      * - https://forum.openzeppelin.com/t/any-good-advanced-math-libraries-looking-for-square-root-ln-cumulative-distributions/2911
    */
    
    function optimalExp(uint256 x) internal pure returns (uint256) {
        uint256 constant FIXED_1 = 0x080000000000000000000000000000000;
        uint256 res = 0;

        uint256 y;
        uint256 z;

        z = y = x % 0x10000000000000000000000000000000; // get the input modulo 2^(-3)
        z = z * y / FIXED_1; res += z * 0x10e1b3be415a0000; // add y^02 * (20! / 02!)
        z = z * y / FIXED_1; res += z * 0x05a0913f6b1e0000; // add y^03 * (20! / 03!)
        z = z * y / FIXED_1; res += z * 0x0168244fdac78000; // add y^04 * (20! / 04!)
        z = z * y / FIXED_1; res += z * 0x004807432bc18000; // add y^05 * (20! / 05!)
        z = z * y / FIXED_1; res += z * 0x000c0135dca04000; // add y^06 * (20! / 06!)
        z = z * y / FIXED_1; res += z * 0x0001b707b1cdc000; // add y^07 * (20! / 07!)
        z = z * y / FIXED_1; res += z * 0x000036e0f639b800; // add y^08 * (20! / 08!)
        z = z * y / FIXED_1; res += z * 0x00000618fee9f800; // add y^09 * (20! / 09!)
        z = z * y / FIXED_1; res += z * 0x0000009c197dcc00; // add y^10 * (20! / 10!)
        z = z * y / FIXED_1; res += z * 0x0000000e30dce400; // add y^11 * (20! / 11!)
        z = z * y / FIXED_1; res += z * 0x000000012ebd1300; // add y^12 * (20! / 12!)
        z = z * y / FIXED_1; res += z * 0x0000000017499f00; // add y^13 * (20! / 13!)
        z = z * y / FIXED_1; res += z * 0x0000000001a9d480; // add y^14 * (20! / 14!)
        z = z * y / FIXED_1; res += z * 0x00000000001c6380; // add y^15 * (20! / 15!)
        z = z * y / FIXED_1; res += z * 0x000000000001c638; // add y^16 * (20! / 16!)
        z = z * y / FIXED_1; res += z * 0x0000000000001ab8; // add y^17 * (20! / 17!)
        z = z * y / FIXED_1; res += z * 0x000000000000017c; // add y^18 * (20! / 18!)
        z = z * y / FIXED_1; res += z * 0x0000000000000014; // add y^19 * (20! / 19!)
        z = z * y / FIXED_1; res += z * 0x0000000000000001; // add y^20 * (20! / 20!)
        res = res / 0x21c3677c82b40000 + y + FIXED_1; // divide by 20! and then add y^1 / 1! + y^0 / 0!

        if ((x & 0x010000000000000000000000000000000) != 0) res = res * 0x1c3d6a24ed82218787d624d3e5eba95f9 / 0x18ebef9eac820ae8682b9793ac6d1e776; // multiply by e^2^(-3)
        if ((x & 0x020000000000000000000000000000000) != 0) res = res * 0x18ebef9eac820ae8682b9793ac6d1e778 / 0x1368b2fc6f9609fe7aceb46aa619baed4; // multiply by e^2^(-2)
        if ((x & 0x040000000000000000000000000000000) != 0) res = res * 0x1368b2fc6f9609fe7aceb46aa619baed5 / 0x0bc5ab1b16779be3575bd8f0520a9f21f; // multiply by e^2^(-1)
        if ((x & 0x080000000000000000000000000000000) != 0) res = res * 0x0bc5ab1b16779be3575bd8f0520a9f21e / 0x0454aaa8efe072e7f6ddbab84b40a55c9; // multiply by e^2^(+0)
        if ((x & 0x100000000000000000000000000000000) != 0) res = res * 0x0454aaa8efe072e7f6ddbab84b40a55c5 / 0x00960aadc109e7a3bf4578099615711ea; // multiply by e^2^(+1)
        if ((x & 0x200000000000000000000000000000000) != 0) res = res * 0x00960aadc109e7a3bf4578099615711d7 / 0x0002bf84208204f5977f9a8cf01fdce3d; // multiply by e^2^(+2)
        if ((x & 0x400000000000000000000000000000000) != 0) res = res * 0x0002bf84208204f5977f9a8cf01fdc307 / 0x0000003c6ab775dd0b95b4cbee7e65d11; // multiply by e^2^(+3)

        return res;
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