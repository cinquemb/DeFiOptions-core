pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface ITurnstile {
    function register(address) external returns(uint256);
    function assign(uint256) external returns(uint256);
    function isRegistered(address _smartContract) external view returns (bool);
}