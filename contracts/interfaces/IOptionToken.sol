pragma solidity >=0.6.0;

interface IOptionToken {
    function name() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function burn(uint value) external;
    function burn(address owner, uint value) external;
    function writtenVolume(address owner) external view returns (uint);
    function uncoveredVolume(address owner) external view returns (uint);
    function permit(
        address owner, 
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}