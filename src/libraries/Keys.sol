// SPDX-License-Identifier: MIT
pragma solidity =0.8.28;

library Keys {
    // Each key module is attached to a contract address of each key model
    // These keys reprensent address of
    bytes32 internal constant _ANNOUNCE_ORDERS_KEY = bytes32("AnnounceOrders");
    bytes32 internal constant _ORACLE_KEY = bytes32("oracles");
    bytes32 internal constant _KEEPER_FEE_KEY = bytes32("KeeperFee");
    bytes32 internal constant _LIQUIDATION_KEY = bytes32("Liquidation");
}
