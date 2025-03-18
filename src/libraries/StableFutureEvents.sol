// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {StableFutureStructs} from "./StableFutureStructs.sol";

library StableFutureEvents {
    // Emit when a user provide liquidity by announcing an orders first.
    event OrderAnnounced(address account, StableFutureStructs.OrderType orderType, uint256 keeperFee);

    // Emit when tokens are minted to LPs
    event Deposit(address account, uint256 depositAmount, uint256 mintedAmount);

    // Emit when tokens are burn and collateral withdrawn
    event Withdraw(address account, uint256 depositAmount, uint256 mintedAmount);

    // Emit when an deposit is executed
    event DepositExecuted(address account, StableFutureStructs.OrderType orderType, uint256 keeperFee);

    event NewchainlinkOracleSet(StableFutureStructs.ChainlinkOracle newOracle);

    event NewPythNetworkOracleSet(StableFutureStructs.PythNetworkOracle newOracle);

    event AssetSet(address newAsset);

    event MaxPriceDiffPerecentSet(uint256 maxPriceDiffPercent);

    event FundingFeesSettled(int256 settleFundingFees);

    event LiquidationFeeRatioModified(uint256 oldRatio, uint256 newRatio);
    event LiquidationBufferRatioModified(uint256 oldBufferRatio, uint256 newBufferRatio);
    event LiquidationFeeBoundsModified(
        uint256 oldLowerBoundFee, uint256 oldUpperBoundfee, uint256 newLowerBoundFee, uint256 newUpperBoundFee
    );
}
