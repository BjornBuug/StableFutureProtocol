// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ProxyAdmin} from "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from
    "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {MockPyth} from "pyth-sdk-solidity/MockPyth.sol";
import {IPyth} from "pyth-sdk-solidity/IPyth.sol";

/**
 * IMPORT CONTRACTS ****************************
 */
import {AnnounceOrders} from "src/AnnounceOrders.sol";
import {StableFutureVault} from "src/StableFutureVault.sol";
import {Oracles} from "src/Oracles.sol";

/**
 * LIBRARIES ****************************
 */
import {StableFutureStructs} from "src/libraries/StableFutureStructs.sol";
import {StableModuleKeys} from "src/libraries/StableModuleKeys.sol";

/**
 * INTERFACES ****************************
 */
import {IChainlinkAggregatorV3} from "src/interfaces/IChainlinkAggregatorV3.sol";
import {IStableFutureVault} from "src/interfaces/IStableFutureVault.sol";
import {IKeeperFee} from "src/interfaces/IKeeperFee.sol";

import "forge-std/Test.sol";
import "forge-std/console2.sol";

abstract contract Setup is Test {
    /**
     * ACCOUNTS ****************************
     */
    address internal admin = makeAddr("Admin");
    address internal alice = makeAddr("Alice");
    address internal bob = makeAddr("Bob");
    address internal david = makeAddr("David");
    address internal keeper = makeAddr("Keeper");
    address internal treasury = makeAddr("Treasury");
    address[] internal accounts = [admin, alice, bob, david, keeper, treasury];

    /**
     * MOCKS ****************************
     */
    IChainlinkAggregatorV3 internal wetChainlinkAggregatorV3 = IChainlinkAggregatorV3(makeAddr("chainlinkAggregatorV3"));

    ERC20 internal WETH;
    MockPyth internal mockPyth;
    IKeeperFee internal mockKeeperFee;

    /**
     * SYSTEM CONTRACTS ****************************
     */

    /**
     * IMPLEMENTATION ****************************
     */
    address internal announceOrdersImplementation;
    address internal oraclesImplementation;
    address internal vaultImplementation;

    /**
     * PROXIES ****************************
     */
    ProxyAdmin internal proxyAdmin;
    AnnounceOrders internal announceOrdersProxy;
    Oracles internal oraclesProxy;
    StableFutureVault internal vaultProxy;

    function setUp() public virtual {
        vm.startPrank(admin);

        // Deploy mocks contracts;

        // WETH = new ERC20("WETH Mocks", "WETH");
        mockPyth = new MockPyth(60, 1);
        // mockKeeperFee = new NOTe: Add later

        // Deploy the proxy admin for all system contract
        proxyAdmin = new ProxyAdmin(address(admin));

        // Deploy implementation for all the system
        announceOrdersImplementation = address(new AnnounceOrders());
        oraclesImplementation = address(new Oracles());
        vaultImplementation = address(new StableFutureVault());

        // Deploy the proxies using the above implementation
        announceOrdersProxy = AnnounceOrders(
            address(new TransparentUpgradeableProxy(announceOrdersImplementation, address(proxyAdmin), ""))
        );

        oraclesProxy = Oracles(address(new TransparentUpgradeableProxy(oraclesImplementation, address(proxyAdmin), "")));

        vaultProxy =
            StableFutureVault(address(new TransparentUpgradeableProxy(vaultImplementation, address(proxyAdmin), "")));
    }
}
