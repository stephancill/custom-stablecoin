// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {StablecoinFactory} from "src/StablecoinFactory.sol";

import {StablecoinFactoryTest} from "test/lib/StablecoinFactoryTest.sol";

/// @dev Unit tests for the UUPS upgrade path (_authorizeUpgrade via upgradeToAndCall).
contract StablecoinFactoryUpgradeToAndCallTest is StablecoinFactoryTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies upgradeToAndCall reverts for any caller without DEFAULT_ADMIN_ROLE
    /// @dev Access control: _authorizeUpgrade is gated on onlyRole(DEFAULT_ADMIN_ROLE)
    function test_upgradeToAndCall_revert_unauthorized(address caller) public {
        vm.assume(caller != admin);
        StablecoinFactory newImpl = new StablecoinFactory(address(beacon));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, factory.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(caller);
        factory.upgradeToAndCall(address(newImpl), "");
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies the admin can upgrade the factory implementation and role state is preserved
    /// @dev UUPS: DEFAULT_ADMIN upgrades impl; DEPLOYER_ROLE persists in proxy storage across the upgrade
    function test_upgradeToAndCall_success_preservesState() public {
        StablecoinFactory newImpl = new StablecoinFactory(address(beacon));
        vm.prank(admin);
        factory.upgradeToAndCall(address(newImpl), "");

        // Role state persists across the impl swap, so the deployer can still issue tokens.
        assertTrue(factory.hasRole(factory.DEPLOYER_ROLE(), deployer));
        address token = _deploy();
        assertGt(token.code.length, 0);
    }
}
