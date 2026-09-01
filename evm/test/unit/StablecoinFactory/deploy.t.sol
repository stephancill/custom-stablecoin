// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {IB20Stablecoin} from "base-std/interfaces/IB20Stablecoin.sol";

import {StablecoinFactory} from "src/StablecoinFactory.sol";

import {StablecoinFactoryTest} from "test/lib/StablecoinFactoryTest.sol";

/// @dev Unit tests for deploy() and computeAddress(). computeAddress tests are merged here
/// because the core invariant is that the computed address equals the issued token address.
contract StablecoinFactoryDeployTest is StablecoinFactoryTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies deploy reverts for any caller without DEPLOYER_ROLE
    /// @dev Access control: onlyRole(DEPLOYER_ROLE) must reject all unauthorized callers
    function test_deploy_revert_unauthorized(address caller) public {
        vm.assume(caller != deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, factory.DEPLOYER_ROLE()
            )
        );
        vm.prank(caller);
        factory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin, DEPLOY_SALT);
    }

    /// @notice Verifies deploy reverts when the same salt is used twice
    /// @dev Deterministic address collision: issuing to the same address twice must revert
    function test_deploy_revert_saltReused(bytes32 salt) public {
        address predicted = _computeAddress(salt);
        _deploy(salt);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.TokenAlreadyExists.selector, predicted));
        _deploy(salt);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies deploy returns an address with contract code
    /// @dev State: the returned address must have code.length > 0 after issuance
    function test_deploy_success_issuesToken(string calldata name, string calldata symbol) public {
        vm.prank(deployer);
        address token = factory.deploy(name, symbol, TOKEN_CURRENCY, stablecoinAdmin, DEPLOY_SALT);
        assertGt(token.code.length, 0);
    }

    /// @notice Verifies deploy emits StablecoinDeployed with the correct parameters
    /// @dev Event integrity: all emitted fields must match the deploy arguments
    function test_deploy_success_emitsStablecoinDeployed(bytes32 salt) public {
        address predicted = _computeAddress(salt);
        vm.expectEmit(true, true, true, true);
        emit StablecoinFactory.StablecoinDeployed({
            stablecoin: predicted,
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            currency: TOKEN_CURRENCY,
            stablecoinAdmin: stablecoinAdmin,
            salt: salt
        });
        _deploy(salt);
    }

    /// @notice Verifies the issued token address matches the address returned by computeAddress
    /// @dev Determinism: the B-20 address must be predictable before issuance
    function test_deploy_success_matchesComputedAddress(bytes32 salt) public {
        address predicted = _computeAddress(salt);
        address issued = _deploy(salt);
        assertEq(issued, predicted);
    }

    /// @notice Verifies the issued token carries the requested name, symbol, and currency, and fixed 6 decimals
    /// @dev Integration: the STABLECOIN create params must be forwarded to the precompile correctly
    function test_deploy_success_initializesStablecoin(string calldata name, string calldata symbol) public {
        vm.prank(deployer);
        address token = factory.deploy(name, symbol, TOKEN_CURRENCY, stablecoinAdmin, DEPLOY_SALT);
        IB20Stablecoin sc = IB20Stablecoin(token);
        assertEq(sc.name(), name);
        assertEq(sc.symbol(), symbol);
        assertEq(sc.currency(), TOKEN_CURRENCY);
        assertEq(sc.decimals(), 6);
    }

    /// @notice Verifies the issued token grants DEFAULT_ADMIN_ROLE to the specified stablecoinAdmin
    /// @dev Integration: the initialAdmin create param must be wired through to a role grant
    function test_deploy_success_setsStablecoinAdmin(address stablecoinAdmin_, bytes32 salt) public {
        vm.assume(stablecoinAdmin_ != address(0));
        vm.prank(deployer);
        address token = factory.deploy(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin_, salt);
        IB20Stablecoin sc = IB20Stablecoin(token);
        assertTrue(sc.hasRole(sc.DEFAULT_ADMIN_ROLE(), stablecoinAdmin_));
    }

    // ── computeAddress ────────────────────────────────────────────────────────────────────

    /// @notice Verifies computeAddress returns different addresses for different salts
    /// @dev Determinism: distinct salts must produce distinct addresses
    function test_computeAddress_success_deterministicForDistinctSalts(bytes32 salt1, bytes32 salt2) public view {
        vm.assume(salt1 != salt2);
        assertNotEq(_computeAddress(salt1), _computeAddress(salt2));
    }

    /// @notice Verifies computeAddress is stable before and after issuance
    /// @dev Idempotent: calling computeAddress before and after deploy() must return the same address
    function test_computeAddress_success_stableAcrossDeployment(bytes32 salt) public {
        address before = _computeAddress(salt);
        address issued = _deploy(salt);
        address after_ = _computeAddress(salt);
        assertEq(before, issued);
        assertEq(before, after_);
    }
}
