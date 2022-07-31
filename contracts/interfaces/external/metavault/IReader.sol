// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12 <0.9.0;

interface IReader {
    function getPositions(address _vault, address _account, address[] memory _collateralTokens, address[] memory _indexTokens, bool[] memory _isLong) public view returns(uint256[] memory);
}
