// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {SafeDecimalMath} from "./SafeDecimalMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {StableFutureStructs} from "./StableFutureStructs.sol";

library PerpMath {
    using SignedMath for int256;
    using SafeDecimalMath for int256;
    using SafeDecimalMath for uint256;

    function _calcUnrecordedFunding(int256 _currentFundingRate, int256 _prevFundingRate, uint256 _prevFundingTimestamp)
        internal
        returns (int256)
    {
        // calculte the average of the current funding rate + previous funding rate
        int256 avgFundingRate = (_currentFundingRate + _prevFundingRate) / 2;
        // calculate the average funding rate over the elapsed time since the last time the funding rate was updated.
        return avgFundingRate._multiplyDecimal(int256(_proportionalElapsedTime(_prevFundingTimestamp)));
    }

    function _fundingChangeSinceRecomputed(
        int256 _propotionalSkew,
        uint256 _prevFundingTimeStamp,
        uint256 _maxFundingVelocity,
        uint256 _maxSkewVelocity
    ) internal returns (int256) {
        // calculate the funding rate changes since last time was updated
        // formula: fundinVelocity * timeElapsed / 1e18
        return _accruedFundingVelocity(_propotionalSkew, _maxFundingVelocity, _maxSkewVelocity)._multiplyDecimal(
            int256(_proportionalElapsedTime(_prevFundingTimeStamp))
        );
    }

    function updateCumulativeFundingRate(int256 _unrecordedFunding, int256 _currentCumulativeFunding)
        internal
        view
        returns (int256)
    {
        return _unrecordedFunding + _currentCumulativeFunding;
    }

    function _calcAccruedTotalFundingByLongs(
        StableFutureStructs.GlobalPosition memory _globalPosition,
        int256 _unrecordedFunding
    ) internal view returns (int256 totalAccruedFunding) {
        // ** if unrecorded funding > 0 => markPrice > indexPrice => long pay shorts
        // accruedFundingTotal = -100e18 * 0.25e18 = - result => the function returns -accruedFundingTotal
        // to be used inside the settle funding to deduct from the total margin of longs.
        // ** if unrecorded funding => 0 markPrice < index(spot) price => shorts pay longs
        // accruedFundingTotal = -100e18 * -0.25e18 = + result => the function returns +accruedFundingTotal
        // to be used inside the the settle funding and add it to the total margin of longs.
        // formula: totalSizeOpened * unrecordedFunding
        totalAccruedFunding = -int256(_globalPosition.totalOpenedPositions)._multiplyDecimal(_unrecordedFunding);

        // NOTE: added 1 wei to the total funding accrued by long to avoid rounding issue.
        return (totalAccruedFunding != 0) ? totalAccruedFunding + 1 : totalAccruedFunding;
    }

    // calculte the time elapsed between the last funding rate blocktimestamp and the current block.timestamp
    // normalize it in days
    function _proportionalElapsedTime(uint256 _prevFundingTimeStamp) internal view returns (uint256 elapsedTime) {
        return (block.timestamp - _prevFundingTimeStamp)._divideDecimal(1 days);
    }

    function _accruedFundingVelocity(int256 _propotionalSkew, uint256 _maxFundingVelocity, uint256 _maxSkewVelocity)
        internal
        view
        returns (int256 currfundingVelocity)
    {
        // check if the _propotionalSkew is greater thn zero
        if (_propotionalSkew > 0) {
            currfundingVelocity = _propotionalSkew * int256(_maxFundingVelocity) / int256(_maxSkewVelocity);
            // make sure currfundingVelocity whitin maxfundinVelocity to present the fundingRate of rising too quickly
            return int256(_maxFundingVelocity).min(currfundingVelocity.max(-int256(_maxFundingVelocity)));
        }
        // no capping if _propotional skew is negative because more it get negative
        // more it makes the funding rate decreased and make it attractive for longs to open longs positions.
        // which wil spend up the reblancing process of the market
        return _propotionalSkew._multiplyDecimal(int256(_maxFundingVelocity));
    }

    function _calcPropotionalSkew(int256 _skew, uint256 _totalDepositedLiquidity)
        internal
        view
        returns (int256 pSkew)
    {
        if (_totalDepositedLiquidity > 0) {
            // normalize the skew by total liquidity deposited
            pSkew = _skew._divideDecimal(int256(_totalDepositedLiquidity));

            // ensure that pskew should always be between -1e18 & 1e18(cap it)
            if (pSkew < -1e18 || pSkew > 1e18) {
                pSkew = SafeDecimalMath.UNIT.min(pSkew.max(-SafeDecimalMath.UNIT));
            }
        } else {
            assert(_skew == 0);
            pSkew = 0;
        }
    }
}
