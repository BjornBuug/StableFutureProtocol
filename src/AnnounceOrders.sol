// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

import {ReentrancyGuardUpgradeable} from 
        "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {IStableFutureVault} from "./interfaces/IStableFutureVault.sol";
import {StableModuleKeys} from "./libraries/StableModuleKeys.sol";
import {ModuleUpgradeable} from "./abstracts/ModuleUpgradeable.sol";
import {StableFutureStructs} from "./libraries/StableFutureStructs.sol";
import {StableFutureEvents} from "./libraries/StableFutureEvents.sol";
import {StableFutureErrors} from "./libraries/StableFutureErrors.sol";
import {IOracles} from "./interfaces/IOracles.sol";
import {IKeeperFee} from "./interfaces/IKeeperFee.sol";
import {ERC20LockableUpgradeable} from "./utilities/ERC20LockableUpgradeable.sol";
import {OraclesModifiers} from "./abstracts/OraclesModifiers.sol";

// TODO
/**
 * NOTE:
 *     - The code inside a constructor or part of a global variable declaration is not part of a deployed contract's runtime bytecode
 *     This code is only executed once. Because is only executed once, the code withing the logic contract(implementation)
 *     will never be executed in the context of the proxy's state.
 *     Because of the proxy designed, proxies are not aware at all of the state changes made by the constructor.
 *     To solve this logic(implementation contract) and in order for the proxy to be aware of the state changes in the implementation
 *     contract. we shouldn't use constructor but mode all the code within the constructor to the regular function Initilize.
 *     - The constructor runs only once to initilize the contract's state(__ReentrancyGuard_init, owner, etc), After deployment
 *     the initilization code is not needed as it's doesn't have to be part of the bytescode in the contracts deployement.
 */

/// @notice Contains functions that allow RETH liquidity providers to announce orders and execute delayed orders via a keeper.
// TODO: Add IAnnounceOrders to the contracts.
contract AnnounceOrders is ReentrancyGuardUpgradeable, ModuleUpgradeable, OraclesModifiers {
    // Minimum deposit amount for LP to deposit.
    uint256 public constant MIN_DEPOSIT = 1e16;

    /// @dev Mapping containing all the orders in an encoded format.
    mapping(address account => StableFutureStructs.Order order) public _announcedOrder;

    using SafeERC20 for IERC20;
    using SignedMath for int256;

    IOracles public OraclesContract;

    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    /// function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the orders module with a reference to the vault
     * @param _vault The StableFutureVault contract address this module will interact with.
     */
    function initialize(IStableFutureVault _vault) external initializer {
        __init_Module(StableModuleKeys._ANNOUNCE_ORDERS_MODULE_KEY, _vault);
        __ReentrancyGuard_init();
    }

    /**
     * @dev Announces a deposit order, allowing keepers to execute it after a specified time.
     * @param depositAmount The amount of collateral to be deposited.
     * @param minAmountOut The minimum amount of SFR tokens expected from the deposit.
     * @param keeperFee The fee paid to the keeper for executing the deposit.
     */
    function announceDeposit(uint256 depositAmount, uint256 minAmountOut, uint256 keeperFee) public whenNotPaused {
        // Calculate the time when the order should be executable by the keeper
        uint64 executableAtTime = _orderExecutionTime(keeperFee);

        // Check for minimum deposit
        if (depositAmount < MIN_DEPOSIT) {
            revert StableFutureErrors.AmountToSmall({depositAmount: depositAmount, minDeposit: MIN_DEPOSIT});
        }

        // Check what is the expected amount out based on the user deposit to check for slippage
        uint256 expectedAmountOut = vault.depositQuote(depositAmount);

        /// Check for slippage
        if (expectedAmountOut < minAmountOut) {
            revert StableFutureErrors.HighSlippage({amountOut: expectedAmountOut, accepted: minAmountOut});
        }

        // record the announceDeposit order in the _announceOrdermapping [x]
        _announcedOrder[msg.sender] = StableFutureStructs.Order({
            orderType: StableFutureStructs.OrderType.Deposit,
            orderData: abi.encode(
                StableFutureStructs.AnnouncedLiquidityDeposit({depositAmount: depositAmount, minAmountOut: minAmountOut})
            ),
            keeperFee: keeperFee,
            executableAtTime: executableAtTime
        });


        // Transfer rETh from msg.sender to this address(this) which will transfer it later to the vault when the annonced order is executed(x)
        vault.collateral().safeTransferFrom(msg.sender, address(this), depositAmount + keeperFee);

        // Emit Event
        emit StableFutureEvents.OrderAnnounced({
            account: msg.sender,
            orderType: StableFutureStructs.OrderType.Deposit,
            keeperFee: keeperFee
        });
    }

    function annonceWithdraw(uint256 withdrawAmount, uint256 minAmountOut, uint256 keeperFee) public whenNotPaused {
        // 1- calculate how much rETH the user will withdraw by burning a certain amount LP token
        uint64 executableAtTime = _orderExecutionTime(keeperFee);

        // Check if the user has enough SFR token to announce withdraw
        uint256 userBalance = IERC20(address(vault)).balanceOf(msg.sender);

        if (userBalance < withdrawAmount) {
            revert StableFutureErrors.InvalidBalance();
        }

        {
            uint256 expectedAmountOut = vault.withdrawQuote(withdrawAmount);

            // expected Amount Out should always be greater than KeeperFees
            if (expectedAmountOut <= keeperFee) {
                revert StableFutureErrors.WithdrawToSmall();
            }

            // Deduct keeper Feee before checking for slippage
            // Since we pay the keeper with rETH we must deduct the keeperFee before checking for slippage.
            expectedAmountOut -= keeperFee;

            if (expectedAmountOut < minAmountOut) {
                revert StableFutureErrors.HighSlippage({amountOut: expectedAmountOut, accepted: minAmountOut});
            }
        }

        // Lock the withdrawAmount of SFR tokens  in the contract to make sure the user doesn't transfer them once they
        // announce withdraw
        // NOTE: Locked tokens doesn't required users approvals
        // withdrawAmount refers to the shares (ERC20 SFR tokens) that the user owns in the pool by depositing rETH
        vault.lock({account: msg.sender, amount: withdrawAmount});

        // Store the order announcement info
        _announcedOrder[msg.sender] = StableFutureStructs.Order({
            orderType: StableFutureStructs.OrderType.Withdraw,
            orderData: abi.encode(
                StableFutureStructs.AnnouncedLiquidityWithdraw({withdrawAmount: withdrawAmount, minAmountOut: minAmountOut})
            ),
            keeperFee: keeperFee,
            executableAtTime: executableAtTime
        });

        emit StableFutureEvents.OrderAnnounced({
            account: msg.sender,
            orderType: StableFutureStructs.OrderType.Withdraw,
            keeperFee: keeperFee
        });
    }

    function executeOrder(address account, bytes[] calldata updatePriceData)
        external
        payable
        whenNotPaused
        nonReentrant
        UpdatePythPrice(vault, msg.sender, updatePriceData)
    {
        // Make sure that keeper doens't passed an empty array to avoid price update
        if (updatePriceData.length == 0) {
            revert StableFutureErrors.updatePriceDataEmpty();
        }

        // 1- Internal function to update the price of Pyth each time this function is called for the user to get the most recent
        // price for his order to be executed.
        // OraclesContract.updatePythPrice(account, updatePriceData);

        // get the orderType of the account
        StableFutureStructs.OrderType orderType = _announcedOrder[account].orderType;

        if (orderType == StableFutureStructs.OrderType.None) return;

        if (orderType == StableFutureStructs.OrderType.Deposit) {
            _executeAnnounceDeposit(account);
        } else if (orderType == StableFutureStructs.OrderType.Withdraw) {
            _executeAnnounceWithdraw(account);
        }
    }

    // Exercices => function allow the keeper to execute executeAnnouncewithdraw.
    // Params: address account returns amount(check it out later)
    function _executeAnnounceWithdraw(address account) internal returns (uint256 amountOut) {
        // 1- retrieves the announcedOrder of the account;
        StableFutureStructs.Order memory order = _announcedOrder[account];

        // Decode the orderdata
        StableFutureStructs.AnnouncedLiquidityWithdraw memory liquidityWithdraw =
            abi.decode(order.orderData, (StableFutureStructs.AnnouncedLiquidityWithdraw));

        // Check if the order exexutableTime is valid
        _orderTimeValidity(account, order.executableAtTime);

        uint256 withdrawFee;

        (amountOut, withdrawFee) = vault._executeWithdraw(account, liquidityWithdraw);

        // The amount that the user will receive the KeeperFee, WithdrawFee would be deducted
        uint256 totalFees = order.keeperFee + withdrawFee;

        if (amountOut <= totalFees) {
            revert StableFutureErrors.notEnoughMarginForFee();
        }

        amountOut -= totalFees;

        if (amountOut < liquidityWithdraw.minAmountOut) {
            revert StableFutureErrors.HighSlippage({amountOut: amountOut, accepted: liquidityWithdraw.minAmountOut});
        }

        // Send rETh collateral back to the account
        vault.sendCollateral({to: account, amount: amountOut});
        vault.sendCollateral({to: msg.sender, amount: order.keeperFee});

        emit StableFutureEvents.DepositExecuted({
            account: account,
            orderType: order.orderType,
            keeperFee: order.keeperFee
        });
    }

    /**
     * @dev Executes a previously announced deposit order for the specified account.
     * @param account The account for which the deposit order will be executed.
     * @return liquidityMinted The amount of liquidity minted as a result of the deposit.
     */
    function _executeAnnounceDeposit(address account) internal returns (uint256 liquidityMinted) {
        // Get the users order
        StableFutureStructs.Order memory order = _announcedOrder[account];

        // Decode the data inside order.orderData
        StableFutureStructs.AnnouncedLiquidityDeposit memory liquidityDeposit =
            abi.decode(order.orderData, (StableFutureStructs.AnnouncedLiquidityDeposit));

        _orderTimeValidity(account, order.executableAtTime);

        liquidityMinted = IStableFutureVault(vault)._executeDeposit(account, liquidityDeposit);

        // Transfer fees to the keeper
        vault.collateral().safeTransfer({to: msg.sender, value: order.keeperFee});

        // Transfer depositAmount to the vault
        vault.collateral().safeTransfer({to: address(vault), value: liquidityDeposit.depositAmount});

        emit StableFutureEvents.DepositExecuted({
            account: account,
            orderType: order.orderType,
            keeperFee: order.keeperFee
        });
    }

    /**
     * @dev Checks the validity of an order's execution time and deletes the order if valid.
     * @param account The account associated with the order.
     * @param _executableAtTime The timestamp when the order becomes executable.
     */
    function _orderTimeValidity(address account, uint256 _executableAtTime) internal {
        // Check if the order didn't expired
        if (block.timestamp > _executableAtTime + vault.maxExecutabilityAge()) {
            revert StableFutureErrors.OrderHasExpired();
        }

        // Check if the order reached the executableAtTime
        if (block.timestamp < _executableAtTime) {
            revert StableFutureErrors.ExecutableAtTimeNotReached(_executableAtTime);
        }

        // delete the announce deposit if both condition doesn't revert
        delete _announcedOrder[account];
    }

    /////////////////////////////////////////////
    //            View Functions             //
    /////////////////////////////////////////////

    /**
     * @dev Calculates the future timestamp when an order becomes executable.
     * @return executeAtTime The timestamp at which a new order will become executable, based on the vault's minimum executability age.
     */
    function _orderExecutionTime(uint256 _keeperFee) private view returns (uint64 executeAtTime) {
        // Todo: Cancel pending orders
        // Check for Minmum amount of keeperFee
        // settle fundingFees

        // @audit-info setModules when doing unit test
        if (_keeperFee < IKeeperFee(vault.moduleAddress(StableModuleKeys._KEEPER_FEE_MODULE_KEY)).getKeeperFee()) {
            revert StableFutureErrors.InvalidFee(_keeperFee);
        }

        return executeAtTime = uint64(block.timestamp + vault.minExecutabilityAge());
    }
}
