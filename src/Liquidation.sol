// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

// contracts
import {ReentrancyGuardUpgradeable} from
    "openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {ModuleUpgradeable} from "src/abstracts/ModuleUpgradeable.sol";

// Lib
import {StableFutureStructs} from "src/libraries/StableFutureStructs.sol";
import {StableFutureErrors} from "src/libraries/StableFutureErrors.sol";
import {StableFutureEvents} from "src/libraries/StableFutureEvents.sol";
import {Keys} from "src/libraries/Keys.sol";

// interface
import {ILiquidation} from "src/interfaces/ILiquidation.sol";
import {IStableFutureVault} from "src/interfaces/IStableFutureVault.sol";

contract Liquidation is ModuleUpgradeable, ReentrancyGuardUpgradeable, ILiquidation {
    /// @dev To prevent the implementation contract from being used, we invoke the _disableInitializers
    ///      function in the constructor to automatically lock it when it is deployed.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IStableFutureVault _vault) public initializer {
        __Module_init(Keys._LIQUIDATION_KEY, _vault);
        __ReentrancyGuard_init();
    }
}
