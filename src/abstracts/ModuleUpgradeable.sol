// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IStableFutureVault} from "../interfaces/IStableFutureVault.sol";
import {StableFutureErrors} from "../libraries/StableFutureErrors.sol";
import {IOracles} from "../interfaces/IOracles.sol";

abstract contract ModuleUpgradeable {
    bytes32 public MODULE_KEY;

    // Define the interface of the StableFutureVault contract
    IStableFutureVault public vault;

    // Define the oracle interface

    // Only owner modifier
    modifier onlyVaultOwner() {
        if (OwnableUpgradeable(address(vault)).owner() != msg.sender) {
            revert StableFutureErrors.OnlyVaultOwner(msg.sender);
        }
        _;
    }

    modifier whenNotPaused() {
        if (vault.isModulePaused(MODULE_KEY)) {
            revert StableFutureErrors.Paused(MODULE_KEY);
        }
        _;
    }

    /**
     * Create a function that allow to set the encode version of the key module and the vault address each time 
     *     we initilize new upgradable conract
     *     1- has 2 params
     *     2- Check if the module exist and check that the vault is not address(0)
     */

    /// @notice Setter for the vault contract.
    /// @dev Can be used in case StableFutureVault ever changes.
    function setVault(IStableFutureVault _vault) external onlyVaultOwner {
        if (address(_vault) == address(0)) {
            revert StableFutureErrors.ZeroAddress("vault");
        }

        vault = _vault;
    }

    /// @dev Function to initilize the module
    /// @param _moduleKey the bytes32 encoded key of the module
    /// @param _vault StableFutureVault address
    function __init_Module(bytes32 _moduleKey, IStableFutureVault _vault) internal {
        if (_moduleKey == bytes32("")) {
            revert StableFutureErrors.ModuleKeyEmpty();
        }
        if (address(_vault) == address(0)) {
            revert StableFutureErrors.ZeroAddress("vault");
        }
        MODULE_KEY = _moduleKey;
        vault = _vault;
    }

    // Add Gaps in case we want to add more variable later for a specific contract
    uint256[48] private __gap;
}
