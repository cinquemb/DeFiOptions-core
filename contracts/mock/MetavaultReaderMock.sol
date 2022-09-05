// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/ManagedContract.sol";


contract MetavaultReaderMock is ManagedContract {
    function getPositions(address _vault, address _account, address[] calldata _collateralTokens, address[] calldata _indexTokens, bool[] calldata _isLong) external view returns(uint256[] memory) {
        uint256[] memory d = new uint256[](2);
        return d;
    }
}
