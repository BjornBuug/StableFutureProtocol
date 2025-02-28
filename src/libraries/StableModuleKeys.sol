// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.28;

library StableModuleKeys {
    // Each key module is attached to an contract address of each key model. stableModule.sol
    bytes32 internal constant _ANNOUNCE_ORDERS_MODULE_KEY = bytes32("AnnounceOrdersModule");
    bytes32 internal constant _ORACLE_MODULE_KEY = bytes32("oraclesModule");
    bytes32 internal constant _KEEPER_FEE_MODULE_KEY = bytes32("KeeperFeeModule");
}
