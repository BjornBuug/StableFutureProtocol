// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {StableFutureStructs} from "./libraries/StableFutureStructs.sol";
import {StableFutureErrors} from "./libraries/StableFutureErrors.sol";
import {StableFutureEvents} from "./libraries/StableFutureEvents.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20LockableUpgradeable} from "./utilities/ERC20LockableUpgradeable.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

/// TODO:
// + move functions that calculte fundings to library contract
// + add natspec

/// @title StableFutureVault
/// @notice Contains state to be reused by different modules/contracts of the system.
/// @dev Holds the rETH deposited by liquidity providers

contract StableFutureVault is OwnableUpgradeable, ERC20LockableUpgradeable, ModuleUpgradeable {
    using SafeERC20 for IERC20;
    using SignedMath for int256;
    using SafeCast for int256;
    using SafeCast for uint256;

    StableFutureStructs.GlobalPosition _globalPosition;

    uint256 lastRecomputedFundingTimestamp;
    uint256 maxFundingVelocity;
    uint256 maxSkewVelocity;

    // represent 1.0 unit
    int256 public constant UNIT = 1e18;

    /// @notice collateral deposited by the LP to get StableFuture Token
    IERC20 public collateral;

    /// @notice The minimum time that needs to expire between trade announcement and execution.
    uint64 public minExecutabilityAge;

    /// @notice The maximum amount of time that can expire between trade announcement and execution.
    uint64 public maxExecutabilityAge;

    /// @notice The total amount of RETH deposited in the vault
    uint256 public lpTotalDepositedLiquidity;

    /// @notice Max amount of liquidity to be deposited in the vault by LP
    uint256 public lpTotalDepositedLiquidityCap;

    /// @notice Minimum liquidity to provide as a first depositor
    uint256 public constant MIN_LIQUIDITY = 10_000;

    // the last recomputed funding rat
    int256 public lastRecomputedFundingRate;

    /// @notice module to bool to pause and unpause a contract module
    mapping(bytes32 moduleKey => bool paused) public isModulePaused;

    /// @notice Keys to module address
    mapping(bytes32 moduleKey => address moduleAddress) public moduleAddress;

    /// @notice module address to bool
    mapping(address moduleAddress => bool authorized) public isAuthorizedModule;

    // @notice withdrawColateraFee taken by the protocol for every withdraw
    uint256 public withdrawCollateralFee;

    /// @dev To prevent the implementation contract from being used, we should invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    } // on deployment time(it's not save on EVM)

    /**
     * @dev Initializes the contract
     * @param _owner The owner of the contract.
     * @param _collateral The collateral token address.
     * @param _minExecutabilityAge Minimum age for executability of orders.
     * @param _maxExecutabilityAge Maximum age for executability of orders.
     */
    function initialize(
        address _owner,
        IERC20 _collateral,
        uint64 _minExecutabilityAge,
        uint64 _maxExecutabilityAge,
        uint256
    ) external initializer {
        // <= can only be called once on the proxy contract level
        if (_owner == address(0)) {
            revert StableFutureErrors.ZeroAddress("Owner");
        }
        if (address(_collateral) == address(0)) {
            revert StableFutureErrors.ZeroAddress("Collateral");
        }

        __Ownable_init(msg.sender);
        _transferOwnership(_owner);
        __ERC20_init("Stable Future", "SFR");

        collateral = _collateral;

        setExecutabilityAge(_minExecutabilityAge, _maxExecutabilityAge);
        setWithdrawCollateralFee(withdrawCollateralFee);
    } // Contract runtime deployment(bytes code executed on EVM)

    modifier onlyAuthorizedModule() {
        if (isAuthorizedModule[msg.sender] == false) {
            revert StableFutureErrors.OnlyAuthorizedModule(msg.sender);
        }
        _;
    }

    // Collateral can only be transfered by authorized contracts/Module set by the Admin
    function transferCollateral(address to, uint256 amount) external onlyAuthorizedModule {
        collateral.safeTransfer(to, amount);
    }

    /**
     * @dev Mints liquidity tokens based on deposited amount, ensuring minimum output and pool requirements are met.
     * @param account The account receiving the liquidity tokens.
     * @param liquidityDeposit Contains deposit amount and minimum output required.
     * @return liquidityMinted Amount of liquidity tokens minted.
     */
    function _executeDeposit(address account, StableFutureStructs.AnnouncedLiquidityDeposit calldata liquidityDeposit)
        external
        onlyAuthorizedModule
        whenNotPaused
        returns (uint256 liquidityMinted)
    {
        // cach variables
        uint256 depositAmount = liquidityDeposit.depositAmount;
        uint256 minAmountOut = liquidityDeposit.minAmountOut;

        liquidityMinted = vault.depositQuote(depositAmount);

        if (liquidityMinted < minAmountOut) {
            revert StableFutureErrors.HighSlippage({amountOut: liquidityMinted, accepted: minAmountOut});
        }

        _mint(account, liquidityMinted);

        // update total deposit in the pool
        _updateLpTotalDepositedLiquidity(int256(depositAmount));

        // Check if the liquidity provided respect the min liquidity to provide to avoid inflation
        // attacks and position with small amount of tokens
        if (totalSupply() < MIN_LIQUIDITY) {
            revert StableFutureErrors.AmountToSmall({depositAmount: totalSupply(), minDeposit: MIN_LIQUIDITY});
        }

        // TODO: Implement point system later
        emit StableFutureEvents.Deposit(account, depositAmount, liquidityMinted);
    }

    function _executeWithdraw(
        address _account,
        StableFutureStructs.AnnouncedLiquidityWithdraw calldata liquidityWithraw
    ) external whenNotPaused onlyAuthorizedModule returns (uint256 _amountOut, uint256 _withdrawFee) {
        // 1- calculate how much the user will get out based on the CollaterPerShare and withdrawAmount
        uint256 _collateralPerShare = collateralPerShare();
        uint256 withdrawAmount = liquidityWithraw.withdrawAmount;

        _amountOut = ((withdrawAmount * _collateralPerShare) / 10 ** decimals());

        // calculate the _withdrawFee user must pay before withdraw
        _withdrawFee = (withdrawCollateralFee * _amountOut) / 1e18;

        // Unlock SFR tokens from the vault before burn
        _unlock(_account, withdrawAmount);

        // Burn SFR tokens
        _burn(_account, withdrawAmount);

        // update the lpTotalDepositedLiquidity;
        _updateLpTotalDepositedLiquidity(-int256(_amountOut));

        emit StableFutureEvents.Withdraw(_account, withdrawAmount, _amountOut);
    }

    function setAuthorizedModule(StableFutureStructs.AuthorizedModule calldata _module) public onlyVaultOwner {
        if (_module.moduleKey == bytes32(0)) {
            revert StableFutureErrors.ZeroValue("moduleKey");
        }

        if (_module.moduleAddress == address(0)) {
            revert StableFutureErrors.ZeroAddress("moduleAddress");
        }

        moduleAddress[_module.moduleKey] = _module.moduleAddress;
        isAuthorizedModule[_module.moduleAddress] = true;
    }

    function setMultipleAuthorizedModule(StableFutureStructs.AuthorizedModule[] calldata _modules)
        external
        onlyVaultOwner
    {
        uint8 modulesLength = uint8(_modules.length);

        for (uint8 i; i < modulesLength; i++) {
            setAuthorizedModule(_modules[i]);
        }
    }

    /////////////////////////////////////////////
    //            View Functions             //
    /////////////////////////////////////////////

    /**
     * @dev Calculates the total deposit value per share of the pool.
     * @return _collateralPerShare The amount of deposit per share, scaled by `10 ** decimals()`.
     */
    function collateralPerShare() internal view returns (uint256 _collateralPerShare) {
        uint256 totalSupply = totalSupply();

        if (totalSupply > 0) {
            _collateralPerShare = (lpTotalDepositedLiquidity * (10 ** decimals())) / totalSupply;
        } else {
            _collateralPerShare = 1e18;
        }
    }

    /**
     * @dev Estimates the amount of liquidity tokens to be minted for a given deposit amount.
     * @param _depositAmount The amount of tokens being deposited.
     * @return _amountOut Estimated liquidity tokens to be minted.
     */
    function depositQuote(uint256 _depositAmount) external view returns (uint256 _amountOut) {
        _amountOut = (_depositAmount * (10 ** decimals())) / collateralPerShare();
    }

    function withdrawQuote(uint256 _withdrawAmount) external view returns (uint256 _amountOut) {
        _amountOut = (_withdrawAmount * collateralPerShare()) / (10 ** decimals());

        // deducte protocol fees from the amoutOut
        _amountOut -= ((_amountOut * withdrawCollateralFee) / 1e18); // 1000 * 5e16(5%) / 1e18(100%)
    }

    // NOTE: Allow only this contract/Module to called this function or other contract can called it
    // If it's only called by this contract I'll set it up to private
    // THIS function must be added to the execute announcedDeposit to update the lpTotalDepositedLiquidity
    /**
     * @dev Updates the total deposit amount in the vault with a new deposit.
     * @param _adjustedLiquidityAmount Amount to
     */
    function updateLpTotalDepositedLiquidity(int256 _adjustedLiquidityAmount) public onlyAuthorizedModule {
        _updateLpTotalDepositedLiquidity(_adjustedLiquidityAmount);
    }

    /// @dev check if the new deposited liquidity amount in the vault doesn't execced cap
    function verifyTotalDepsitedLiquidityCap(uint256 _depositedAmount) public view {
        uint256 newTotalDepositedLiquidity = lpTotalDepositedLiquidity + _depositedAmount;
        if (newTotalDepositedLiquidity > lpTotalDepositedLiquidityCap) {
            revert StableFutureErrors.DepositCapReached("newTotalDepositedLiquidity");
        }
    }

    function _updateLpTotalDepositedLiquidity(int256 _adjustedLiquidityAmount) private {
        int256 newTotalDepositedLiquidity = int256(lpTotalDepositedLiquidity) + _adjustedLiquidityAmount;

        if (newTotalDepositedLiquidity < 0) revert StableFutureErrors.valueNotPositive("newTotalDepositedLiquidity");
        lpTotalDepositedLiquidity = newTotalDepositedLiquidity.toUint256();
    }

    // revert if the current deposited margin by traders is negative
    // so the protocol doesn't take more positions to not owe funding for more than it has in deposit
    function verifyGlobalMarginStatus() public {
        int256 currentGlobalMargin = _globalPosition.totalDepositedMargin;
        if (currentGlobalMargin < 0) revert StableFutureErrors.InsufficientGlobalMargin();
    }

    /**
     * @dev calculate funding fees between longs and LPs
     * @notice If funding fees positive, long pays shorts and vice versa
     */
    function settleFundingFees() public {
        // get unrecoded funding fees since last calculation
        (int256 fundingChangeSinceRecomputed, int256 unrecordedFunding) = _getUnrecordedFunding();

        // update the lastest funding rate and block timestamp
        lastRecomputedFundingRate += fundingChangeSinceRecomputed;
        lastRecomputedFundingTimestamp += (block.timestamp).toUint64();

        int256 accruedFundingFees = _calcAccruedTotalFundingByLongs(unrecordedFunding);

        // Adjust longs margin
        // if accruedFundingFees is negative(longspayshorts) we deduct from margin else we add to margin(shortPayLong)
        _globalPosition.totalDepositedMargin = _globalPosition.totalDepositedMargin + accruedFundingFees;

        // Adjust Short deposited liquidity
        // If accruedFundingFees is negative(longspayshorts) we add to shorts deposited liquidity else deduct from it(shortPayLong)
        _updateLpTotalDepositedLiquidity(-accruedFundingFees);

        emit StableFutureEvents.FundingFeesSettled(accruedFundingFees);
    }

    function _calcAccruedTotalFundingByLongs(int256 unrecordedFunding)
        internal
        view
        returns (int256 totalAccruedFunding)
    {
        // ** if unrecorded funding > 0 => markPrice > indexPrice => long pay shorts
        // accruedFundingTotal = -100e18 * 0.25e18 = - result => the function returns -accruedFundingTotal
        // to be used inside the settle funding to deduct from the total margin of longs.
        // ** if unrecorded funding => markPrice < index(spot) price => shorts pay longs
        // accruedFundingTotal = -100e18 * -0.25e18 = + result => the function returns +accruedFundingTotal
        // to be used inside the the settle funding and add it to the total margin of longs.
        // formula: totalSizeOpened * unrecordedFunding
        totalAccruedFunding = -int256(_globalPosition.totalOpenedPositions) * unrecordedFunding / UNIT;

        // NOTE: added 1 wei to the total funding accrued by long to avoid rounding issue.
        return (totalAccruedFunding != 0) ? totalAccruedFunding + 1 : totalAccruedFunding;
    }

    /**
     * @dev calculate the unrecorded funding amount based on market skew ans time elapsed
     */
    function _getUnrecordedFunding() internal returns (int256 fundingChangeSinceRecomputed, int256 unrecordedFunding) {
        // calculte how imbalance the market is(skew)
        // formula: TotalOpenPosition - 'totalliquidity deposited by Liquidity providers
        int256 propotionalSkew = _calcPropotionalSkew({
            _skew: int256(_globalPosition.totalDepositedMargin) - int256(lpTotalDepositedLiquidity),
            _totalDepositedLiquidity: lpTotalDepositedLiquidity
        });

        // Calculates how much the funding rate has changed since the last update.
        fundingChangeSinceRecomputed = _fundingChangeSinceRecomputed({
            _propotionalSkew: propotionalSkew,
            _prevFundingTimeStamp: lastRecomputedFundingTimestamp,
            _maxFundingVelocity: maxFundingVelocity,
            _maxSkewVelocity: maxSkewVelocity
        });

        // calculte total unrecorded funding accured since the last settelement
        unrecordedFunding = _calcUnrecordedFunding({
            _currentFundingRate: fundingChangeSinceRecomputed + lastRecomputedFundingRate,
            _prevFundingRate: lastRecomputedFundingRate,
            _prevFundingTimestamp: lastRecomputedFundingTimestamp
        });
    }

    function _calcUnrecordedFunding(int256 _currentFundingRate, int256 _prevFundingRate, uint256 _prevFundingTimestamp)
        internal
        returns (int256)
    {
        // calculte the average of the current funding rate + previous funding rate
        int256 avgFundingRate = (_currentFundingRate + _prevFundingRate) / 2;
        // calculate the average funding rate over the elapsed time since the last time the funding rate was updated.
        return avgFundingRate * int256(_proportionalElapsedTime(_prevFundingTimestamp)) / UNIT;
    }

    function _fundingChangeSinceRecomputed(
        int256 _propotionalSkew,
        uint256 _prevFundingTimeStamp,
        uint256 _maxFundingVelocity,
        uint256 _maxSkewVelocity
    ) internal returns (int256) {
        // calculate the funding rate changes since last time was updated
        // formula: fundinVelocity * timeElapsed / 1e18
        return _accruedFundingVelocity(_propotionalSkew, _maxFundingVelocity, _maxSkewVelocity)
            * int256(_proportionalElapsedTime(_prevFundingTimeStamp)) / UNIT;
    }

    // calculte the time elapsed between the last funding rate blocktimestamp and the current block.timestamp
    // normalize it in days
    function _proportionalElapsedTime(uint256 _prevFundingTimeStamp) internal view returns (uint256 elapsedTime) {
        return (block.timestamp - _prevFundingTimeStamp) * uint256(UNIT) / 1 days;
    }

    function _accruedFundingVelocity(int256 _propotionalSkew, uint256 _maxFundingVelocity, uint256 _maxSkewVelocity)
        internal
        view
        returns (int256 currfundingVelocity)
    {
        // check if the _propotionalSkew is greater thn zero
        if (_propotionalSkew > 0) {
            currfundingVelocity = _propotionalSkew * int256(_maxFundingVelocity) / int256(_maxSkewVelocity);
            // make sure fundingVelocity whitin maxfundinVelocity to present the fundingRat of rising too quickly
            return int256(maxFundingVelocity).min(currfundingVelocity.max(-int256(maxFundingVelocity)));
        }
        // no capping if _propotional skew is negative because more it get negative
        // more it makes the funding rate decreased and make it attractive for longs to open take longs positions.
        // which wil spend up the reblancing process of the market
        return _propotionalSkew * int256(_maxFundingVelocity) / UNIT;
    }

    function _calcPropotionalSkew(int256 _skew, uint256 _totalDepositedLiquidity) private view returns (int256 pSkew) {
        if (_totalDepositedLiquidity > 0) {
            // normalize the skew by total liquidity deposited
            pSkew = _skew * UNIT / int256(_totalDepositedLiquidity);

            // ensure that pskew should always be between -1e18 & 1e18(cap it)
            if (pSkew < -1e18 || pSkew > 1e18) {
                pSkew = UNIT.min(pSkew.max(-UNIT));
            }
        } else {
            assert(_skew == 0);
            pSkew = 0;
        }
    }

    /////////////////////////////////////////////
    //            Setter Functions             //
    /////////////////////////////////////////////

    /**
     * @dev Sets the minimum and maximum age for an order's executability.
     * @param _minExecutabilityAge The minimum age an order must reach to be executable.
     * @param _maxExecutabilityAge The maximum age an order can reach before it's no longer executable.
     */
    function setExecutabilityAge(uint64 _minExecutabilityAge, uint64 _maxExecutabilityAge) public onlyVaultOwner {
        if (_minExecutabilityAge == 0) {
            revert StableFutureErrors.ZeroValue("minExecutabilityAge");
        }
        if (_maxExecutabilityAge == 0) {
            revert StableFutureErrors.ZeroValue("maxExecutabilityAge");
        }
        minExecutabilityAge = _minExecutabilityAge;
        maxExecutabilityAge = _maxExecutabilityAge;
    }

    function pauseModule(bytes32 _moduleKey) external onlyVaultOwner {
        isModulePaused[_moduleKey] = true;
    }

    function unpauseModule(bytes32 _moduleKey) external onlyVaultOwner {
        isModulePaused[_moduleKey] = false;
    }

    function setWithdrawCollateralFee(uint256 _withdrawCollateralFee) public onlyVaultOwner {
        // MaxFee = 1% = 1e16
        if (_withdrawCollateralFee < 0 || _withdrawCollateralFee > 1e16) {
            revert StableFutureErrors.InvalidValue(_withdrawCollateralFee);
        }
        withdrawCollateralFee = _withdrawCollateralFee;
    }

    function lock(address account, uint256 amount) public onlyAuthorizedModule {
        _lock(account, amount);
    }

    function unlock(address account, uint256 amount) public onlyAuthorizedModule {
        _unlock(account, amount);
    }
}
