pragma solidity >=0.6.0;

interface IOptionTokenFactory {
    function create(string calldata symbol, address udlFeed) external returns (address);
}