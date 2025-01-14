pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

import "../deployment/Deployer.sol";
import "../finance/RedeemableToken.sol";
import "../utils/ERC20.sol";
import "../utils/Arrays.sol";
import "../utils/SafeMath.sol";
import "../interfaces/IUnderlyingVault.sol";

contract OptionToken is RedeemableToken {

    using SafeMath for uint;

    mapping(address => uint) private _issued;

    string private constant _prefix = "DeFi Options DAO Option Redeemable Token: ";
    string private _symbol;
    uint private _unliquidatedVolume;
    address vaultAddr;

    constructor(string memory _sb, address _issuer, address _deployer)
        ERC20(string(abi.encodePacked(_prefix, _sb)))
        public
    {    
        _symbol = _sb;
        exchange = IOptionsExchange(_issuer);
        Deployer deployer = Deployer(_deployer);
        vaultAddr = deployer.getContractAddress("UnderlyingVault");
    }

    function name() override external view returns (string memory) {
        return string(abi.encodePacked(_prefix, _symbol));
    }

    function symbol() override external view returns (string memory) {

        return _symbol;
    }

    function issue(address from, address to, uint value) external {

        require(msg.sender == address(exchange), "issuance unallowed");
        _issued[from] = _issued[from].add(value);
        addBalance(to, value);
        _totalSupply = _totalSupply.add(value);
        _unliquidatedVolume = _unliquidatedVolume.add(value);
        emit Transfer(address(0), to, value);
    }

    function burn(uint value) external {

        burn(msg.sender, value);
    }

    function burn(address owner, uint value) public {

        require(
            msg.sender == owner || msg.sender == address(exchange),
            "burn sender unallowed"
        );

        uint b = balanceOf(owner);
        uint w = _issued[owner];
        require(
            b >= value && w >= value || (msg.sender == address(exchange) && w >= value),
            "invalid burn value"
        );

        if (msg.sender == owner) {
            removeBalance(owner, value);
            _totalSupply = _totalSupply.sub(value);
        }
        
        uint uc = uncoveredVolume(owner);
        uint coll = MoreMath.min(value, uc);

        w = w.sub(value);
        _issued[owner] = w;
        _unliquidatedVolume = _unliquidatedVolume.sub(value);

        uint udl = value > uc ? value.sub(uc) : 0;

        exchange.release(owner, udl, coll);
        exchange.cleanUp(owner, address(this));

        if (msg.sender == owner) {
            emit Transfer(owner, address(0), value);
        }
    }

    function writtenVolume(address owner) external view returns (uint) {

        return _issued[owner];
    }

    function totalWrittenVolume() public view returns (uint) {
        return _unliquidatedVolume;
    }

    function uncoveredVolume(address owner) public view returns (uint) {
        uint covered = IUnderlyingVault(vaultAddr).balanceOf(owner, address(this));
        uint w = _issued[owner];
        return w > covered ? w.sub(covered) : 0;
    }

    function redeemAllowed() override public view returns (bool) {
        
        return _unliquidatedVolume == 0;
    }

    function afterRedeem(address owner, uint bal, uint) override internal {
        exchange.cleanUp(owner, address(this));
        emit Transfer(owner, address(0), bal);
    }

    function emitTransfer(address from, address to, uint value) override internal {

        exchange.transferOwnership(_symbol, from, to, value);
        emit Transfer(from, to, value);
    }
}