// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


interface IReader {
    function getPositions(address _vault, address _account, address[] calldata _collateralTokens, address[] calldata _indexTokens, bool[] calldata _isLong) external view returns(uint256[] memory);
}
