pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IInterpolator {
    function interpolate (int udlPrice, uint32 t0, uint32 t1, uint120[] calldata x, uint120[] calldata y, uint f) external view returns (uint price);
}