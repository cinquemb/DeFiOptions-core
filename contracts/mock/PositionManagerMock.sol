// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/ManagedContract.sol";


contract PositionManagerMock is ManagedContract  {
    function vault() external view returns (address) {
        return address(0);
    }

    function router() external view returns (address) {
        return address(0);
    }

    function increasePosition(
        address[] calldata _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price,
        bytes32 _referralCode
    ) external {

    }

    function increasePositionETH(
        address[] calldata _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _price,
        bytes32 _referralCode
    ) external payable {

    }

    function decreasePosition(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price,
        bytes32 _referralCode
    ) external {

    }

    function decreasePositionETH(
        address _collateralToken,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price
    ) external {

    }

    function decreasePositionAndSwap(
        address[] calldata _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _price,
        uint256 _minOut,
        bytes32 _referralCode
    ) external {

    }

    function decreasePositionAndSwapETH(
        address[] calldata _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address payable _receiver,
        uint256 _price,
        uint256 _minOut
    ) external {

    }
}
