// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12 <0.9.0;

interface IPositionManager {
    function vault() public view returns (address);
}
