// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BaseTest} from "base-std-test/lib/BaseTest.sol";

import {StablecoinFactory} from "src/StablecoinFactory.sol";

/// @dev Base test contract for StablecoinFactory. Extends base-std's {BaseTest}, which etches the
/// B-20 precompile mocks (factory, policy registry, activation registry) and activates the
/// STABLECOIN feature, then deploys a UUPS-proxied factory and initializes it. All factory test
/// files inherit from this.
///
/// The `admin` and `attacker` actors are inherited from {BaseTest}.
contract StablecoinFactoryTest is BaseTest {
    // ── Actors ───────────────────────────────────────────────────────────────────────────
    address internal deployer = makeAddr("deployer");
    address internal stablecoinAdmin = makeAddr("stablecoinAdmin");

    // ── Contracts ────────────────────────────────────────────────────────────────────────
    StablecoinFactory internal factory;

    // ── Defaults ─────────────────────────────────────────────────────────────────────────
    string internal constant TOKEN_NAME = "Test USD";
    string internal constant TOKEN_SYMBOL = "TUSD";
    string internal constant TOKEN_CURRENCY = "USD";
    uint48 internal constant ADMIN_DELAY = 0;
    bytes32 internal constant DEPLOY_SALT = bytes32(uint256(1));

    // ── Setup ─────────────────────────────────────────────────────────────────────────────
    function setUp() public virtual override {
        // Etches the B-20 precompile mocks and activates the STABLECOIN feature.
        super.setUp();

        // Wrap the factory in a UUPS proxy and initialize.
        StablecoinFactory factoryImpl = new StablecoinFactory();
        bytes memory factoryInitData = abi.encodeCall(StablecoinFactory.initialize, (admin, ADMIN_DELAY, deployer));
        ERC1967Proxy factoryProxy = new ERC1967Proxy(address(factoryImpl), factoryInitData);
        factory = StablecoinFactory(address(factoryProxy));

        vm.label(address(factory), "StablecoinFactory");
        vm.label(deployer, "deployer");
        vm.label(stablecoinAdmin, "stablecoinAdmin");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────────────────

    /// @dev Issues a stablecoin via the factory with the given salt, default token params, and no initCalls.
    function _deploy(bytes32 salt) internal returns (address) {
        return _deploy(new bytes[](0), salt);
    }

    /// @dev Issues a stablecoin via the factory with the given bootstrap initCalls and salt.
    function _deploy(bytes[] memory initCalls, bytes32 salt) internal returns (address) {
        vm.prank(deployer);
        return factory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin, initCalls, salt);
    }

    /// @dev Issues a stablecoin using the constant DEPLOY_SALT and no initCalls.
    function _deploy() internal returns (address) {
        return _deploy(DEPLOY_SALT);
    }

    /// @dev Computes the expected address for the given salt.
    function _computeAddress(bytes32 salt) internal view returns (address) {
        return factory.computeAddress(salt);
    }
}
