// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {StableFutureStructs} from "./libraries/StableFutureStructs.sol";
import {StableFutureErrors} from "./libraries/StableFutureErrors.sol";
import {StableFutureEvents} from "./libraries/StableFutureEvents.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ERC20LockableUpgradeable} from "./utilities/ERC20LockableUpgradeable.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";

/**
    TODO: 
    Defining the important States variables of the contract:
    - Collateral, [x]
    - MaxAmountOfDeposit, [x]

 */

/// @title StableFutureVault
/// @notice Contains state to be reused by different modules/contracts of the system.
/// @dev Holds the rETH deposited by liquidity providers

contract StableFutureVault is
    OwnableUpgradeable,
    ERC20LockableUpgradeable,
    ModuleUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice collateran deposited by the LP to get StableFuture Token
    IERC20 public collateral;

    /// @notice The minimum time that needs to expire between trade announcement and execution.
    uint64 public minExecutabilityAge;

    /// @notice The maximum amount of time that can expire between trade announcement and execution.
    uint64 public maxExecutabilityAge;

    /// @notice The total amount of RETH deposited in the vault
    uint256 public totalVaultDeposit;

    /// @notice Minimum liquidity to provide as a first depositor
    uint256 public constant MIN_LIQUIDITY = 10_000;

    /// @notice module to bool to pause and unpause a contract module
    mapping(bytes32 moduleKey => bool paused) public isModulePaused;

    /// @notice Keys to module address
    mapping(bytes32 moduleKey => address moduleAddress) public moduleAddress;

    /// @notice module address to bool
    mapping(address moduleAddress => bool authorized) public isAuthorizedModule;

    // @notice withdrawColateraFee taken by the protocol for every withdraw
    uint256 public withdrawCollateralFee;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
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
        if (_owner == address(0))
            revert StableFutureErrors.ZeroAddress("Owner");
        if (address(_collateral) == address(0))
            revert StableFutureErrors.ZeroAddress("Collateral");

        __Ownable_init(msg.sender);
        _transferOwnership(_owner);
        __ERC20_init("Stable Future", "SFR");

        collateral = _collateral;

        setExecutabilityAge(_minExecutabilityAge, _maxExecutabilityAge);
        setWithdrawCollateralFee(withdrawCollateralFee);
    } // Contract runtime deployment(bytes code executed on EVM)

    modifier onlyAuthorizedModule() {
        if (isAuthorizedModule[msg.sender] == false)
            revert StableFutureErrors.OnlyAuthorizedModule(msg.sender);
        _;
    }

    /**
     * @dev Mints liquidity tokens based on deposited amount, ensuring minimum output and pool requirements are met.
     * @param account The account receiving the liquidity tokens.
     * @param liquidityDeposit Contains deposit amount and minimum output required.
     * @return liquidityMinted Amount of liquidity tokens minted.
     */
    function _executeDeposit(
        address account,
        StableFutureStructs.AnnouncedLiquidityDeposit calldata liquidityDeposit
    )
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
            revert StableFutureErrors.HighSlippage({
                amountOut: liquidityMinted,
                accepted: minAmountOut
            });
        }

        _mint(account, liquidityMinted);

        // update total deposit in the pool
        updateTotalVaulDeposit(depositAmount);

        // Check if the liquidity provided respect the min liquidity to provide to avoid inflation
        // attacks and position with small amount of tokens

        if (totalSupply() < MIN_LIQUIDITY) {
            revert StableFutureErrors.AmountToSmall({
                depositAmount: totalSupply(),
                minDeposit: MIN_LIQUIDITY
            });
        }

        // TODO: Implement point system later
        emit StableFutureEvents.Deposit(
            account,
            depositAmount,
            liquidityMinted
        );
    }

    function setAuthorizedModule(
        StableFutureStructs.AuthorizedModule calldata _module
    ) public onlyVaultOwner {
        if (_module.moduleKey == bytes32(0))
            revert StableFutureErrors.ZeroValue("moduleKey");

        if (_module.moduleAddress == address(0))
            revert StableFutureErrors.ZeroAddress("moduleAddress");

        moduleAddress[_module.moduleKey] = _module.moduleAddress;
        isAuthorizedModule[_module.moduleAddress] = true;
    }

    // Exerice to batch setAddAuthorizedModule
    function setMultipleAuthorizedModule(
        StableFutureStructs.AuthorizedModule[] calldata _modules
    ) external onlyVaultOwner {
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
    function totalDepositPerShare()
        internal
        view
        returns (uint256 _collateralPerShare)
    {
        uint256 totalSupply = totalSupply();

        if (totalSupply > 0) {
            _collateralPerShare =
                (totalVaultDeposit * (10 ** decimals())) /
                totalSupply;
        } else {
            _collateralPerShare = 1e18;
        }
    }

    /**
     * @dev Estimates the amount of liquidity tokens to be minted for a given deposit amount.
     * @param _depositAmount The amount of tokens being deposited.
     * @return _amountOut Estimated liquidity tokens to be minted.
     */
    function depositQuote(
        uint256 _depositAmount
    ) external view returns (uint256 _amountOut) {
        _amountOut =
            (_depositAmount * (10 ** decimals())) /
            totalDepositPerShare();
    }

    function withdrawQuote(
        uint256 _withdrawAmount
    ) external view returns (uint256 _amountOut) {
        _amountOut =
            (_withdrawAmount * totalDepositPerShare()) /
            (10 ** decimals());

        // deducte protocol fees from the amoutOut
        _amountOut -= ((_amountOut * withdrawCollateralFee) / 1e18); // 1000 * 5e16(5%) / 1e18(100%)
    }

    // NOTE: Allow only this contract/Module to called this function or other contract can called it
    // If it's only called by this contract I'll set it up to private
    // THIS function must be added to the execute announcedDeposit to update the totalVaultDeposit
    /**
     * @dev Updates the total deposit amount in the vault with a new deposit.
     * @param _newDeposit Amount to be added to the total vault deposit.
     */
    function updateTotalVaulDeposit(uint256 _newDeposit) public {
        // totalVaultDeposit
        uint256 newTotalVaultDeposit = totalVaultDeposit + _newDeposit;

        totalVaultDeposit = (newTotalVaultDeposit > 0)
            ? newTotalVaultDeposit
            : 0;
    }

    /////////////////////////////////////////////
    //            Setter Functions             //
    /////////////////////////////////////////////

    /**
     * @dev Sets the minimum and maximum age for an order's executability.
     * @param _minExecutabilityAge The minimum age an order must reach to be executable.
     * @param _maxExecutabilityAge The maximum age an order can reach before it's no longer executable.
     */
    function setExecutabilityAge(
        uint64 _minExecutabilityAge,
        uint64 _maxExecutabilityAge
    ) public onlyVaultOwner {
        if (_minExecutabilityAge == 0)
            revert StableFutureErrors.ZeroValue("minExecutabilityAge");
        if (_maxExecutabilityAge == 0)
            revert StableFutureErrors.ZeroValue("maxExecutabilityAge");
        minExecutabilityAge = _minExecutabilityAge;
        maxExecutabilityAge = _maxExecutabilityAge;
    }

    function pauseModule(bytes32 _moduleKey) external onlyVaultOwner {
        isModulePaused[_moduleKey] = true;
    }

    function unpauseModule(bytes32 _moduleKey) external onlyVaultOwner {
        isModulePaused[_moduleKey] = false;
    }

    function setWithdrawCollateralFee(
        uint256 _withdrawCollateralFee
    ) public onlyVaultOwner {
        // MaxFee = 1% = 1e16
        if (_withdrawCollateralFee < 0 || _withdrawCollateralFee > 1e16) {
            revert StableFutureErrors.InvalidValue(_withdrawCollateralFee);
        }
        withdrawCollateralFee = _withdrawCollateralFee;
    }

    function lock(address account, uint256 amount) public onlyAuthorizedModule {
        _lock(account, amount);
    }

    function unlock(
        address account,
        uint256 amount
    ) public onlyAuthorizedModule {
        _unlock(account, amount);
    }
}
