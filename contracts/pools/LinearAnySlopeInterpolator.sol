pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;


import "../deployment/Deployer.sol";
import "../deployment/ManagedContract.sol";
import "../governance/ProtocolSettings.sol";
import "../utils/SafeMath.sol";
import "../utils/SignedSafeMath.sol";

contract LinearAnySlopeInterpolator is ManagedContract {

    using SafeMath for uint;
    using SignedSafeMath for int;
    
    ProtocolSettings private settings;

    uint private fractionBase;

    function initialize(Deployer deployer) override internal {
        
        settings = ProtocolSettings(deployer.getContractAddress("ProtocolSettings"));
        fractionBase = 1e9;
    }

    function interpolate(
        int udlPrice,
        uint32 t0,
        uint32 t1,
        uint120[] calldata x,
        uint120[] calldata y,
        uint f
    )
        external
        view
        returns (uint price)
    {
        (uint j, uint xp) = findUdlPrice(udlPrice, x);
        uint _now = settings.exchangeTime();
        uint dt = uint(t1).sub(uint(t0));
        require(_now >= t0 && _now <= t1, "error interpolate: _now < t0 | _now > t1");
        
        uint t = _now.sub(t0);
        uint p0 = calcOptPriceAt(x, y, 0, j, xp);
        uint p1 = calcOptPriceAt(x, y, x.length, j, xp);

        uint dp0p1 = uint(MoreMath.abs(int(p0).sub(int(p1))));

        if (p0 >= p1) {
            price = p0.mul(dt).sub(
                t.mul(dp0p1)
            ).mul(f).div(fractionBase).div(dt);
        } else {
            price = p0.mul(dt).add(
                t.mul(dp0p1)
            ).mul(f).div(fractionBase).div(dt);
        }
    }

    function findUdlPrice(
        int udlPrice,
        uint120[] memory x
    )
        private
        pure
        returns (uint j, uint xp)
    {
        xp = uint(udlPrice);
        while (x[j] < xp && j < x.length) {
            j++;
        }
        require(j > 0 && j < x.length, "invalid pricing parameters");
    }

    function calcOptPriceAt(
        uint120[] memory x,
        uint120[] memory y,
        uint offset,
        uint j,
        uint xp
    )
        private
        pure
        returns (uint price)
    {
        uint k = offset.add(j);
        require(k < y.length, "error calcOptPriceAt: k >= y.length");
        int yA = int(y[k]);
        int yB = int(y[k.sub(1)]);
        int xN = int(xp.sub(x[j.sub(1)]));
        int xD = int(x[j]).sub(int(x[j.sub(1)]));

        require(xD != 0, "error calcOptPriceAt: xD == 0");

        (int y1, int y2) = (0, 0);
        
        if (yA >= yB) {
            y1 = yA.sub(yB);
            y2 = yB;
        } else {
            y1 = yB.sub(yA);
            y2 = yA;
        }

        price = uint(
            y1.mul(
                xN
            ).div(
                xD
            ).add(y2)
        );
    }
}