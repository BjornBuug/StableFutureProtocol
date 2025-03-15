// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {IChainlinkAggregatorV3} from "../interfaces/IChainlinkAggregatorV3.sol";
import {IPyth} from "pyth-sdk-solidity/IPyth.sol";

library StableFutureStructs {
    enum OrderType {
        None, // 1
        Deposit, // 2
        Withdraw // 3

    }

    /// @notice Global position data
    struct GlobalPosition {
        int256 totalDepositedMargin;
        uint256 averagePrice;
        uint256 totalOpenedPositions;
    }

    struct Order {
        OrderType orderType;
        bytes orderData;
        uint256 keeperFee; // The deposit paid upon submitting that needs to be paid / refunded on tx confirmation
        uint64 executableAtTime; // The timestamp at which this order is executable at
    }

    struct AnnouncedLiquidityDeposit {
        // Amount of liquidity deposited
        uint256 depositAmount;
        // The minimum amount of tokens expected to receive back after providing liquidity
        uint256 minAmountOut;
    }

    struct AnnouncedLiquidityWithdraw {
        // Amount of "SFR" token to withdraw to get collateral.
        uint256 withdrawAmount;
        // The minimum amount of tokens expected to receive back after providing liquidity
        uint256 minAmountOut;
    }

    struct ChainlinkOracle {
        IChainlinkAggregatorV3 chainlinkOracle;
        // the oldest price that is acceptable to use.
        uint32 maxAge;
    }

    struct PythNetworkOracle {
        // Pyth network oracle contract
        IPyth pythNetworkContract;
        // Pyth network priceID
        bytes32 priceId;
        // the oldest price acceptable to use
        uint32 maxAge;
        // Minimum confid ratio aka expo ratio, The higher, the more confident the accuracy of the price.
        uint32 minConfidenceRatio;
    }

    struct AuthorizedModule {
        bytes32 moduleKey;
        address moduleAddress;
    }
}
