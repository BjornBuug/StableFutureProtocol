// SPDX-License-Identifier: BUSL-1.1
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

    // function lastRecomputedFundingTimestamp() external view returns (uint64 lastRecomputedFundingTimestamp);

    function minExecutabilityAge() external view returns (uint64 minExecutabilityAge);

    function maxExecutabilityAge() external view returns (uint64 maxExecutabilityAge);

    // function lastRecomputedFundingRate() external view returns (int256 lastRecomputedFundingRate);

    // function cumulativeFundingRate() external view returns (int256 cumulativeFundingRate);

    // function maxFundingVelocity() external view returns (uint256 maxFundingVelocity);

    // function maxVelocitySkew() external view returns (uint256 maxVelocitySkew);

    function stableCollateralTotal() external view returns (uint256 totalAmount);

    // function skewFractionMax() external view returns (uint256 skewFractionMax);

    function moduleAddress(bytes32 _moduleKey) external view returns (address moduleAddress);

    // function isAuthorizedModule(address _address) external view returns (bool status);

    function isModulePaused(bytes32 moduleKey) external view returns (bool paused);

    function sendCollateral(address to, uint256 amount) external;

    function withdrawQuote(uint256 _withdrawAmount) external view returns (uint256 _amountOut);

    function lock(address account, uint256 amount) external;

    // function getVaultSummary() external view returns (StableFutureStructs.VaultSummary memory _vaultSummary);

    // function getGlobalPositions() external view returns (StableFutureStructs.GlobalPositions memory _globalPositions);

    // function setPosition(StableFutureStructs.Position memory _position, uint256 _tokenId) external;

    // function updateGlobalPositionData(uint256 price, int256 marginDelta, int256 additionalSizeDelta) external;

    // function updateStableCollateralTotal(int256 _stableCollateralAdjustment) external;

    // function addAuthorizedModules(StableFutureStructs.AuthorizedModule[] calldata _modules) external;

    // function addAuthorizedModule(StableFutureStructs.AuthorizedModule calldata _module) external;

    // function removeAuthorizedModule(bytes32 _moduleKey) external;

    // function deletePosition(uint256 _tokenId) external;

    function settleFundingFees() external;

    function verifyGlobalMarginStatus() external;

    // function getCurrentFundingRate() external view returns (int256 fundingRate);

    // function getPosition(uint256 _tokenId) external view returns (StableFutureStructs.Position memory position);

    // function checkSkewMax(uint256 additionalSkew) external view;

    // function checkCollateralCap(uint256 depositAmount) external view;

    // function stableCollateralCap() external view returns (uint256 collateralCap);

    // function getCurrentSkew() external view returns (int256 skew);
}
