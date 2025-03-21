// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {StableFutureStructs} from "./StableFutureStructs.sol";

library StableFutureErrors {
    enum PriceSource {
        chainlinkOracle,
        pythOracle
    }

    error InsufficientGlobalMargin();

    error DepositCapReached(string variableName);

    error ZeroAddress(string variableName);

    error ZeroValue(string variableName);

    error Paused(bytes32 moduleKey);

    error InvalidValue(uint256 value);

    error InvalidBounds(uint256 lowerBound, uint256 upperBound);

    error valueNotPositive(string variableName);

    error OnlyVaultOwner(address msgSender);

    error OnlyAuthorizedModule(address msgSender);

    error ModuleKeyEmpty();

    error HighSlippage(uint256 amountOut, uint256 accepted);

    error OrderHasExpired();

    error InvalidFee(uint256 fee);

    error ExecutableAtTimeNotReached(uint256 executableAtTime);

    error AmountToSmall(uint256 depositAmount, uint256 minDeposit);

    error InvalidOracleConfig();

    error PriceStale(PriceSource priceSource);

    error InvalidPrice(PriceSource priceSource);

    error ExcessivePriceDeviation(uint256 priceDiffPercent);

    error RefundFailed();

    error updatePriceDataEmpty();

    error InvalidBalance();

    error WithdrawToSmall();

    error notEnoughMarginForFee();

    error ETHPriceInvalid();
    error ETHPriceStale();

    error InvalidFeeValue(uint256 fee);

    error NotLiquidatable(uint256 tokenId);
}
