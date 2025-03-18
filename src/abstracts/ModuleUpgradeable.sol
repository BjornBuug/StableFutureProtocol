// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IStableFutureVault} from "src/interfaces/IStableFutureVault.sol";
import {StableFutureErrors} from "src/libraries/StableFutureErrors.sol";
import {IOracles} from "src/interfaces/IOracles.sol";

abstract contract ModuleUpgradeable is Initializable {
    bytes32 public MODULE_KEY;

    IStableFutureVault public vault;

    // Only Vault owner
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

    /// @notice Setter for the vault contract.
    /// @dev Can be used in case StableFutureVault ever changes
    function setVault(IStableFutureVault _vault) external onlyVaultOwner {
        if (address(_vault) == address(0)) {
            revert StableFutureErrors.ZeroAddress("vault");
        }

        vault = _vault;
    }

    /// @dev Function to initilize the module
    /// @param _moduleKey the bytes32 encoded key of the module
    /// @param _vault StableFutureVault address
    function __Module_init(bytes32 _moduleKey, IStableFutureVault _vault) internal {
        if (_moduleKey == bytes32("")) {
            revert StableFutureErrors.ModuleKeyEmpty();
        }
        if (address(_vault) == address(0)) {
            revert StableFutureErrors.ZeroAddress("vault");
        }
        MODULE_KEY = _moduleKey;
        vault = _vault;
    }

    uint256[48] private __gap;
}
