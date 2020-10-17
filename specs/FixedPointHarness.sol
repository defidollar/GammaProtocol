/**
 * SPDX-License-Identifier: UNLICENSED
 */
pragma solidity 0.6.10;

pragma experimental ABIEncoderV2;

import '../contracts/libs/FixedPointInt256.sol';

/**
 * @author Opyn Team
 * @notice FixedPointInt256 contract tester
 */
contract FixedPointHarness {
  using FixedPointInt256 for FixedPointInt256.FixedPointInt;

  function expectedAdd(uint256 _a, uint256 _b) external pure returns (uint256) {
    require(_a < 1000 && _b < 1000);
    uint256 c = ((_a * (1e9)) + (_b * (1e9))) / (1e9);
    return c;
  }

  function testFPI(uint256 _a) external pure returns (uint256) {
    FixedPointInt256.FixedPointInt memory a = FixedPointInt256.fromScaledUint(_a, 18);
    return FixedPointInt256.toScaledUint(a, 18, true);
  }

  function testAdd(uint256 _a, uint256 _b) external pure returns (uint256) {
    FixedPointInt256.FixedPointInt memory a = FixedPointInt256.fromScaledUint(_a, 18);
    FixedPointInt256.FixedPointInt memory b = FixedPointInt256.fromScaledUint(_b, 18);

    FixedPointInt256.FixedPointInt memory c = a.add(b);
    return c.toScaledUint(18, true);
  }

  function expectedMul(
    uint256 _a,
    uint256 _b,
    uint256 _decimals
  ) external pure returns (uint256) {
    uint256 a = _a * 10**(27 - _decimals);
    uint256 b = _b * 10**(27 - _decimals);
    uint256 c = (a * b) / 10**(54 - _decimals);
    return c;
  }

  function testSub(uint256 _a, uint256 _b) external pure returns (uint256) {
    FixedPointInt256.FixedPointInt memory a = FixedPointInt256.fromScaledUint(_a, 18);
    FixedPointInt256.FixedPointInt memory b = FixedPointInt256.fromScaledUint(_b, 18);

    FixedPointInt256.FixedPointInt memory c = a.sub(b);
    return c.toScaledUint(18, true);
  }

  function testMul(
    uint256 _a,
    uint256 _b,
    uint256 _decimals
  ) external pure returns (uint256) {
    FixedPointInt256.FixedPointInt memory a = FixedPointInt256.fromScaledUint(_a, _decimals);
    FixedPointInt256.FixedPointInt memory b = FixedPointInt256.fromScaledUint(_b, _decimals);

    FixedPointInt256.FixedPointInt memory c = a.mul(b);
    return c.toScaledUint(_decimals, true);
  }
}