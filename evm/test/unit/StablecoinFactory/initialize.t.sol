// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {StablecoinFactory} from "src/StablecoinFactory.sol";

import {StablecoinFactoryTest} from "test/lib/StablecoinFactoryTest.sol";

contract StablecoinFactoryInitializeTest is StablecoinFactoryTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies the implementation cannot be initialized directly
    /// @dev InvalidInitialization: the constructor calls _disableInitializers on the implementation
    function test_initialize_revert_implementationDisabled() public {
        StablecoinFactory freshImpl = new StablecoinFactory();
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidInitialization()"))));
        freshImpl.initialize(admin, ADMIN_DELAY, deployer);
    }

    /// @notice Verifies initialize reverts when called on an already-initialized factory
    /// @dev InvalidInitialization: the initializer modifier must prevent re-initialization
    function test_initialize_revert_alreadyInitialized() public {
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("InvalidInitialization()"))));
        factory.initialize(admin, ADMIN_DELAY, deployer);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies initialize grants DEPLOYER_ROLE to the deployer address
    /// @dev Access control: only the deployer should be able to call deploy() after initialization
    function test_initialize_success_grantsDeployerRole(address deployer_) public {
        StablecoinFactory freshFactory = _freshFactory(admin, deployer_);
        assertTrue(freshFactory.hasRole(freshFactory.DEPLOYER_ROLE(), deployer_));
    }

    /// @notice Verifies initialize assigns DEFAULT_ADMIN_ROLE to the admin address
    /// @dev Access control: the admin controls upgrades and role management after initialization
    function test_initialize_success_setsDefaultAdmin(address admin_) public {
        vm.assume(admin_ != address(0));
        StablecoinFactory freshFactory = _freshFactory(admin_, deployer);
        assertTrue(freshFactory.hasRole(freshFactory.DEFAULT_ADMIN_ROLE(), admin_));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────────────────

    /// @dev Deploys a fresh UUPS-proxied factory initialized with the given admin and deployer.
    function _freshFactory(address admin_, address deployer_) internal returns (StablecoinFactory) {
        StablecoinFactory freshImpl = new StablecoinFactory();
        bytes memory initData = abi.encodeCall(StablecoinFactory.initialize, (admin_, ADMIN_DELAY, deployer_));
        return StablecoinFactory(address(new ERC1967Proxy(address(freshImpl), initData)));
    }
}
