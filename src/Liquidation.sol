// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

// contracts
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";

// Lib
import {StableFutureStructs} from "src/libraries/StableFutureStructs.sol";
import {StableFutureErrors} from "src/libraries/StableFutureErrors.sol";
import {StableFutureEvents} from "src/libraries/StableFutureEvents.sol";
import {PerpMath} from "src/libraries/PerpMath.sol";
import {Keys} from "src/libraries/Keys.sol";

// interface
import {ILiquidation} from "src/interfaces/ILiquidation.sol";
import {IOracles} from "src/interfaces/IOracles.sol";
import {IStableFutureVault} from "src/interfaces/IStableFutureVault.sol";

contract Liquidation is ILiquidation, ModuleUpgradeable, ReentrancyGuardUpgradeable {
    // Todo: Add natspecs
    /// @notice liquidation fees in basis point paid to the liquidator
    /// @dev should include 18 decimals. e.g: 0.1% => 0.001e18 => 1e15;
    uint256 public liquidationFeeRatio;

    /// @notice Liquidation buffer ratio in basis points to prevent a margin to be negative at liquidation
    /// @dev should include 18 decimals. e.g: 0.32% => 0.0032e18 => 32e14;
    uint256 public liquidationBufferRatio;

    /// @notice liquidation fee upper bound
    /// @dev measured in USD
    uint256 liquidationFeeUpperBound;

    /// @notice liquidation fee low bound
    /// @dev measured in USD
    uint256 liquidationFeeLowerBound;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    ///      function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IStableFutureVault _vault,
        uint256 _newLiquidationFeeRatio,
        uint256 _newLiquidationBufferRatio,
        uint256 _newLiquidationFeeLowerBound,
        uint256 _newLiquidationFeeUpperBound
    ) public initializer {
        __Module_init(Keys._LIQUIDATION_KEY, _vault);
        __ReentrancyGuard_init();

        setLiquidationFeeRatio(_newLiquidationFeeRatio);
        setLiquidationBufferRatio(_newLiquidationBufferRatio);
        setLiquidationFeeBounds(_newLiquidationFeeLowerBound, _newLiquidationFeeUpperBound);
    }

    function liquidate(uint256 tokenId) public nonReentrant whenNotPaused {
        // settle funding fees accrued till now
        vault.settleFundingFees();

        // check if the position can be liquidated or not
        if (isLiquidatable(tokenId)) revert StableFutureErrors.NotLiquidatable(tokenId);
    }

    // function check if a leverage position can be liquidatable or not
    function isLiquidatable(uint256 tokenId) public view returns (bool liquidatable) {
        // get the current price
        (uint256 currentPrice,) = IOracles(vault.moduleAddress(Keys._ORACLE_KEY)).getPrice();

        isLiquidatable(tokenId, currentPrice);
    }

    function isLiquidatable(uint256 _tokenId, uint256 _currentprice) public view returns (bool) {
        // get the position to check for liquidation
        StableFutureStructs.Position memory _position = vault.getPosition(_tokenId);

        // get accrued funding fees since last re computed to assess the position margin
        int256 nextFundingEntry = _calcNextFundingEntry();

        return PerpMath._isLiquidatable();
    }

    // calcule the current fundin rate
    function _calcNextFundingEntry() public view returns (int256 nextFundingEntry) {
        // calcul proportional skew
        uint256 totalDepositedLiquidity = vault.lpTotalDepositedLiquidity();
        int256 currentMarketSkew =
            int256(vault.getGlobalPositions().totalOpenedPositions) - int256(totalDepositedLiquidity);

        int256 proportionalSkew =
            PerpMath._calcPropotionalSkew({_skew: currentMarketSkew, _totalDepositedLiquidity: totalDepositedLiquidity});

        // currentFunding
        int256 currentFundingRate = PerpMath._calcCurrentFundingRate({
            _propotionalSkew: proportionalSkew,
            _prevFundingTimestamp: vault.lastRecomputedFundingTimestamp(),
            _prevFundingRate: vault.lastRecomputedFundingRate(),
            _maxFundingVelocity: vault.maxFundingVelocity(),
            _maxSkewVelocity: vault.maxSkewVelocity()
        });

        // unrecorded Funding
        int256 unrecordedFunding = PerpMath._calcUnrecordedFunding({
            _currentFundingRate: currentFundingRate,
            _prevFundingRate: vault.lastRecomputedFundingRate(),
            _prevFundingTimestamp: vault.lastRecomputedFundingTimestamp()
        });

        // Update the total cumulitive fundin rate with unrecordedFunding to reflect the current market rate
        return PerpMath._updateCumulativeFundingRate(unrecordedFunding, vault.cumulativeFundingRate());
    }

    function setLiquidationFeeRatio(uint256 _newLiquidationFeeRatio) public onlyVaultOwner {
        if (_newLiquidationFeeRatio == 0) revert StableFutureErrors.ZeroValue("newLiquidationFeeRatio");

        emit StableFutureEvents.LiquidationFeeRatioModified(liquidationFeeRatio, _newLiquidationFeeRatio);

        liquidationFeeRatio = _newLiquidationFeeRatio;
    }

    function setLiquidationBufferRatio(uint256 _newLiquidationBufferRatio) public onlyVaultOwner {
        if (_newLiquidationBufferRatio == 0) revert StableFutureErrors.ZeroValue("newLiquidationBufferRatio");

        emit StableFutureEvents.LiquidationBufferRatioModified(liquidationBufferRatio, _newLiquidationBufferRatio);

        liquidationBufferRatio = _newLiquidationBufferRatio;
    }

    function setLiquidationFeeBounds(uint256 _newLiquidationFeeLowerBound, uint256 _newLiquidationFeeUpperBound)
        public
        onlyVaultOwner
    {
        if (_newLiquidationFeeLowerBound == 0 || _newLiquidationFeeUpperBound == 0) {
            revert StableFutureErrors.ZeroValue("newLiquidationFeeBound");
        }

        if (_newLiquidationFeeUpperBound <= _newLiquidationFeeLowerBound) {
            revert StableFutureErrors.InvalidBounds(_newLiquidationFeeLowerBound, _newLiquidationFeeUpperBound);
        }

        emit StableFutureEvents.LiquidationFeeBoundsModified(
            liquidationFeeLowerBound,
            liquidationFeeUpperBound,
            _newLiquidationFeeLowerBound,
            _newLiquidationFeeUpperBound
        );

        liquidationFeeLowerBound = _newLiquidationFeeLowerBound;
        liquidationFeeUpperBound = _newLiquidationFeeUpperBound;
    }
}
