// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

import {IStableFutureVault} from "src/interfaces/IStableFutureVault.sol";
import {IOracles} from "src/interfaces/IOracles.sol";
import {Keys} from "src/libraries/Keys.sol";

abstract contract OraclesModifiers {
    /// @dev Important to use this modifier in functions which require the Pyth network price to be updated.
    modifier UpdatePythPrice(IStableFutureVault vault, address sender, bytes[] calldata priceUpdateData) {
        IOracles(vault.moduleAddress(Keys._ORACLE_KEY)).updatePythPrice{value: msg.value}(sender, priceUpdateData);
        _;
    }
}
