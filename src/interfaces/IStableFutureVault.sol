// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {StableFutureStructs} from "../libraries/StableFutureStructs.sol";

interface IStableFutureVault {
    function _executeDeposit(address account, StableFutureStructs.AnnouncedLiquidityDeposit calldata liquidityDeposit)
        external
        returns (uint256 liquidityMinted);

    function _executeWithdraw(
        address _account,
        StableFutureStructs.AnnouncedLiquidityWithdraw calldata liquidityWithraw
    ) external returns (uint256 _amountOut, uint256 _withdrawFee);
    function collateral() external view returns (IERC20 collateral);
    function depositQuote(uint256 _depositAmount) external view returns (uint256 _amountOut);
    function minExecutabilityAge() external view returns (uint64 minExecutabilityAge);
    function maxExecutabilityAge() external view returns (uint64 maxExecutabilityAge);
    function stableCollateralTotal() external view returns (uint256 totalAmount);
    function moduleAddress(bytes32 _moduleKey) external view returns (address moduleAddress);
    function isModulePaused(bytes32 moduleKey) external view returns (bool paused);
    function sendCollateral(address to, uint256 amount) external;
    function withdrawQuote(uint256 _withdrawAmount) external view returns (uint256 _amountOut);
    function lock(address account, uint256 amount) external;
    function settleFundingFees() external;
    function verifyGlobalMarginStatus() external;
    function lastRecomputedFundingTimestamp() external view returns (uint256);
    function lastRecomputedFundingRate() external view returns (int256);
    function lpTotalDepositedLiquidity() external view returns (uint256);
    function cumulativeFundingRate() external view returns (int256);
    function maxSkewVelocity() external view returns (uint256);
    function maxFundingVelocity() external view returns (uint256);
    function updateLpTotalDepositedLiquidity(int256 _adjustedLiquidityAmount) external;
    function transferCollateral(address to, uint256 amount) external;

    function getPosition(uint256 tokenId)
        external
        view
        returns (StableFutureStructs.Position memory _positionDetails);

    function getGlobalPositions()
        external
        view
        returns (StableFutureStructs.GlobalPositions memory _globalPositionDetails);
}
