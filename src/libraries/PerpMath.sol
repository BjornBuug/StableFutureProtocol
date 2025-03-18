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
        view
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
    ) internal view returns (int256) {
        // calculate the funding rate changes since last time was updated
        // formula: fundinVelocity * timeElapsed / 1e18
        return _accruedFundingVelocity(_propotionalSkew, _maxFundingVelocity, _maxSkewVelocity)._multiplyDecimal(
            int256(_proportionalElapsedTime(_prevFundingTimeStamp))
        );
    }

    // calculate the current funding rate
    function _calcCurrentFundingRate(
        int256 _propotionalSkew,
        uint256 _prevFundingTimestamp,
        int256 _prevFundingRate,
        uint256 _maxFundingVelocity,
        uint256 _maxSkewVelocity
    ) internal view returns (int256 currentFundingRate) {
        return _prevFundingRate
            + _fundingChangeSinceRecomputed(_propotionalSkew, _prevFundingTimestamp, _maxFundingVelocity, _maxSkewVelocity);
    }

    function _updateCumulativeFundingRate(int256 _unrecordedFunding, int256 _currentCumulativeFunding)
        internal
        pure
        returns (int256)
    {
        return _unrecordedFunding + _currentCumulativeFunding;
    }

    function _calcAccruedTotalFundingByLongs(
        StableFutureStructs.GlobalPositions memory _globalPositions,
        int256 _unrecordedFunding
    ) internal pure returns (int256 totalAccruedFunding) {
        // ** if unrecorded funding > 0 => markPrice > indexPrice => long pay shorts
        // accruedFundingTotal = -100e18 * 0.25e18 = - result => the function returns -accruedFundingTotal
        // to be used inside the settle funding to deduct from the total margin of longs.
        // ** if unrecorded funding => 0 markPrice < index(spot) price => shorts pay longs
        // accruedFundingTotal = -100e18 * -0.25e18 = + result => the function returns +accruedFundingTotal
        // to be used inside the the settle funding and add it to the total margin of longs.
        // formula: totalSizeOpened * unrecordedFunding
        totalAccruedFunding = -int256(_globalPositions.totalOpenedPositions)._multiplyDecimal(_unrecordedFunding);

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
        pure
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
        pure
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

    function _isLiquidatable(
        StableFutureStructs.Position memory position,
        uint256 _currentPrice,
        int256 _nextFundingEntry,
        uint256 _liquidationFeeRatio,
        uint256 _liquidationBufferRatio,
        uint256 _liquidationFeeUpperBound,
        uint256 _liquidationFeeLowerBound
    ) internal view returns (bool) {
        // no need to check for liquidation for an empty position
        if (position.additionalSize == 0) {
            return false;
        }

        // calculte the remaining margin of the position after accounting(+-)
        // losses, profit, accured funding since entry
        StableFutureStructs.PositionRecap memory positionRecap =
            _getPositionRecap(position, _nextFundingEntry, _currentPrice);

        uint256 minLiquidatinMargin = _calcMinLiquidationMargin(
            position,
            _liquidationFeeRatio,
            _liquidationBufferRatio,
            _liquidationFeeUpperBound,
            _liquidationFeeLowerBound,
            _currentPrice
        );

        // Check whether the position is liquidatable or not after settlement (fees, PNL)
        return positionRecap.settledMargin <= int256(minLiquidatinMargin);
    }

    /// @dev min liquidation margin consists of adding buffer & deduction of liquidation fee, keep fee,
    function _calcMinLiquidationMargin(
        StableFutureStructs.Position memory position,
        uint256 _liquidationFeeRatio,
        uint256 _liquidationBufferRatio,
        uint256 _liquidationFeeUpperBound,
        uint256 _liquidationFeeLowerBound,
        uint256 _currentPrice
    ) internal pure returns (uint256 minMargin) {
        // calculate a position with a buffer
        uint256 liquidationBuffer = position.additionalSize._multiplyDecimal(_liquidationBufferRatio);
        return liquidationBuffer
            + _calcLiquidationFee(
                position, _liquidationFeeRatio, _liquidationFeeUpperBound, _liquidationFeeLowerBound, _currentPrice
            );
    }

    //
    function _calcLiquidationFee(
        StableFutureStructs.Position memory position,
        uint256 _liquidationFeeRatio,
        uint256 _liquidationFeeUpperBound,
        uint256 _liquidationFeeLowerBound,
        uint256 _currentPrice
    ) internal pure returns (uint256 liquidationFee) {
        // Formula: positionSize * feeRatio * currentPrice
        uint256 proportionalFee = position.additionalSize * _liquidationFeeRatio * _currentPrice;

        // cap fee to fee upper bound if it exceeds it
        uint256 cappedLiquidationFee =
            proportionalFee > _liquidationFeeUpperBound ? _liquidationFeeUpperBound : proportionalFee;

        // cap fee to fee lower bound if it's below it
        uint256 feeInNumeraire =
            cappedLiquidationFee < _liquidationFeeLowerBound ? _liquidationFeeLowerBound : cappedLiquidationFee;

        // convert fee in USD back to the collateral asset unit
        return feeInNumeraire * 1e18 / _currentPrice;
    }

    function _getPositionRecap(
        StableFutureStructs.Position memory position,
        int256 _nextFundingEntry,
        uint256 _currentPrice
    ) internal pure returns (StableFutureStructs.PositionRecap memory positionRecap) {
        // calculte profit and loss of the position
        int256 profitLoss = _profitLoss(_currentPrice, position);

        // net funding rate (position or negative)
        int256 accrFunding = _accruedFunding(_nextFundingEntry, position);
        int256 marginAfterSettlement = int256(position.marginDeposited) + profitLoss + accrFunding;

        // adjustMargin in position summary after settelemnt
        return StableFutureStructs.PositionRecap({
            profitLoss: profitLoss,
            accruedFunding: accrFunding,
            settledMargin: marginAfterSettlement
        });
    }

    // Calculate the accrued funding fees to pay or receive based on
    // the funding net and position size
    function _accruedFunding(int256 _nextFundingEntry, StableFutureStructs.Position memory position)
        internal
        pure
        returns (int256 accrFunding)
    {
        // calc net funding
        // negative => long pay short
        // positive => short pay long
        int256 net = int256(position.entryCumulativeFunding) - _nextFundingEntry;
        return int256(position.additionalSize)._multiplyDecimal(net);
    }

    function _profitLoss(uint256 _currentPrice, StableFutureStructs.Position memory position)
        internal
        pure
        returns (int256)
    {
        // calculte the price shift between the current price and the entryprice
        int256 priceShift = int256(_currentPrice - position.averageEntryPrice);
        int256 pnl = (int256(position.additionalSize) * (priceShift) * 10) / int256(_currentPrice);
        if (pnl % 10 != 0) {
            // rounding down due to truncation when dividing
            return pnl / 10 - 1;
        } else {
            pnl / 10;
        }
    }
}
