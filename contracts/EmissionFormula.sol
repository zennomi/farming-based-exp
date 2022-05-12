// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {UniV2Math} from "../lib/UniV2Math.sol";

contract EmissionFormula {
    using SafeMath for uint256;
    using UniV2Math for uint256;

    // formula for emission/s
    function getCoefficientU(
        uint256 X,
        uint256 Y,
        uint256 Z
    ) public pure returns (uint256) {
        uint256 k = ((Y.sub(Z)).mul(10**9)).div((Z.sub(X)));

        return k.sub(((k.mul(k)).sub(10**18)).sqrt());
    }

    function getCoefficientC(
        uint256 X,
        uint256 Y,
        uint256 Z,
        uint256 m
    ) public pure returns (uint256) {
        uint256 numerator = (m.mul(10**9)).sub(10 * 9);
        uint256 u = getCoefficientU(X, Y, Z);
        uint256 denominator = u.add(10**9);

        return (numerator.div(denominator)).mul((numerator.div(denominator)));
    }

    function getCoefficientB(
        uint256 X,
        uint256 Y,
        uint256 Z,
        uint256 m
    ) public pure returns (uint256) {
        uint256 u = getCoefficientU(X, Y, Z);

        return ((m.sub(1)).mul(u)).div(u.add(10**9));
    }

    function getCoefficientA(
        uint256 X,
        uint256 Y,
        uint256 Z,
        uint256 m
    ) public pure returns (uint256) {
        uint256 u = getCoefficientU(X, Y, Z);
        uint256 numerator = (Y.sub(Z)).mul(2).mul(m.sub(1)).mul(10**9);
        uint256 denominator = u.add(10**9);

        return (numerator.div(denominator));
    }

    function getEmissionPerSecond(
        uint256 X,
        uint256 Y,
        uint256 Z,
        uint256 m,
        uint256 userCount
    ) public pure returns (uint128) {
        //define u
        uint256 u = getCoefficientU(X, Y, Z);

        //define a
        uint256 a = getCoefficientA(X, Y, Z, m);

        //define b
        uint256 b = getCoefficientB(X, Y, Z, m);

        //define c
        uint256 c = getCoefficientC(X, Y, Z, m);

        uint256 numerator;
        if (userCount > b.add(1)) {
            numerator = a.mul((userCount).sub(b).sub(1));
        } else {
            a.mul((b.add(1)).sub(userCount));
        }
        uint256 denominator;
        if (userCount > b.add(1)) {
            denominator = (((userCount).sub(b).sub(1))**2).add(c);
        } else {
            denominator = (((b.add(1)).sub(userCount))**2).add(c);
        }
        return uint128((numerator.div(denominator)).add(Z));
    }
}
