// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

import {StableFutureStructs} from "./StableFutureStructs.sol";

library StableFutureErrors {
    enum PriceSource {
        chainlinkOracle,
        pythOracle
    }

    error ZeroAddress(string variableName);

    error ZeroValue(string variableName);

    error Paused(bytes32 moduleKey);

    error InvalidValue(uint256 value);

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
}
