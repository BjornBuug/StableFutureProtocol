// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

// Adapted from Synthetix <https://github.com/Synthetixio/synthetix/blob/cbd8666f4331ee95fcc667ec7345d13c8ba77efb/contracts/SignedSafeDecimalMath.sol>
/// and  <https://github.com/Synthetixio/synthetix/blob/cbd8666f4331ee95fcc667ec7345d13c8ba77efb/contracts/SafeDecimalMath.sol>

// TODO: add natspec

library SafeDecimalMath {
    int256 public constant UNIT = 1e18;

    function _multiplyDecimal(int256 x, int256 y) internal pure returns (int256) {
        return (x * y) / UNIT;
    }

    function _multiplyDecimal(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * y) / uint256(UNIT);
    }

    function _divideDecimal(int256 x, int256 y) internal pure returns (int256) {
        return (x * UNIT) / y;
    }

    function _divideDecimal(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * uint256(UNIT)) / y;
    }
}
