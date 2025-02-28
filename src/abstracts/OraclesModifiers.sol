// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

import {IStableFutureVault} from "../interfaces/IStableFutureVault.sol";
import {IOracles} from "../interfaces/IOracles.sol";
import {StableModuleKeys} from "../libraries/StableModuleKeys.sol";

abstract contract OraclesModifiers {
    /// @dev Important to use this modifier in functions which require the Pyth network price to be updated.
    modifier UpdatePythPrice(IStableFutureVault vault, address sender, bytes[] calldata priceUpdateData) {
        IOracles(vault.moduleAddress(StableModuleKeys._ORACLE_MODULE_KEY)).updatePythPrice{value: msg.value}(
            sender, priceUpdateData
        );
        _;
    }
}
