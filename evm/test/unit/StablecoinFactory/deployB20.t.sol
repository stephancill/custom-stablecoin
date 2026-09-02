// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {IB20Stablecoin} from "base-std/interfaces/IB20Stablecoin.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";

import {PolicyRegistryConstants} from "base-std-test/lib/mocks/MockPolicyRegistry.sol";

import {StablecoinFactory} from "src/StablecoinFactory.sol";

import {StablecoinFactoryTest} from "test/lib/StablecoinFactoryTest.sol";

/// @dev Unit tests for deployB20() and computeB20Address(). computeB20Address tests are merged here
/// because the core invariant is that the computed address equals the issued token address.
contract StablecoinFactoryDeployB20Test is StablecoinFactoryTest {
    // ── Reverts ───────────────────────────────────────────────────────────────────────────

    /// @notice Verifies deployB20 reverts for any caller without DEPLOYER_ROLE
    /// @dev Access control: onlyRole(DEPLOYER_ROLE) must reject all unauthorized callers
    function test_deployB20_revert_unauthorized(address caller) public {
        vm.assume(caller != deployer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, caller, factory.DEPLOYER_ROLE()
            )
        );
        vm.prank(caller);
        factory.deployB20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin, new bytes[](0), DEPLOY_SALT);
    }

    /// @notice Verifies deployB20 reverts when the same salt is used twice
    /// @dev Deterministic address collision: issuing to the same address twice must revert
    function test_deployB20_revert_saltReused(bytes32 salt) public {
        address predicted = _computeB20Address(salt);
        _deployB20(salt);
        vm.expectRevert(abi.encodeWithSelector(IB20Factory.TokenAlreadyExists.selector, predicted));
        _deployB20(salt);
    }

    /// @notice Verifies a reverting initCall aborts the whole deployB20, bubbling the inner reason
    /// @dev Bootstrap bundle: an updatePolicy to a non-existent policy bubbles PolicyNotFound
    function test_deployB20_revert_initCallFails(uint64 seed) public {
        uint64 missingPolicyId = _wellFormedUncreatedPolicyId(seed);
        bytes[] memory initCalls = new bytes[](1);
        initCalls[0] = B20FactoryLib.encodeUpdatePolicy(B20Constants.TRANSFER_SENDER_POLICY, missingPolicyId);
        vm.expectRevert(abi.encodeWithSelector(IB20.PolicyNotFound.selector, missingPolicyId));
        _deployB20(initCalls, DEPLOY_SALT);
    }

    // ── Happy paths ───────────────────────────────────────────────────────────────────────

    /// @notice Verifies deployB20 returns an address with contract code
    /// @dev State: the returned address must have code.length > 0 after issuance
    function test_deployB20_success_issuesToken(string calldata name, string calldata symbol) public {
        vm.prank(deployer);
        address token = factory.deployB20(name, symbol, TOKEN_CURRENCY, stablecoinAdmin, new bytes[](0), DEPLOY_SALT);
        assertGt(token.code.length, 0);
    }

    /// @notice Verifies the compliance initCalls bundle is executed on the new token during bootstrap
    /// @dev Bootstrap bundle: updateSupplyCap + updatePolicy are applied before the privileged window closes
    function test_deployB20_success_runsInitCalls(uint256 supplyCap) public {
        supplyCap = bound(supplyCap, 0, B20Constants.MAX_SUPPLY_CAP);

        bytes[] memory initCalls = new bytes[](2);
        initCalls[0] = B20FactoryLib.encodeUpdateSupplyCap(supplyCap);
        initCalls[1] = B20FactoryLib.encodeUpdatePolicy(
            B20Constants.TRANSFER_SENDER_POLICY, PolicyRegistryConstants.ALWAYS_BLOCK_ID
        );

        address token = _deployB20(initCalls, DEPLOY_SALT);

        IB20 sc = IB20(token);
        assertEq(sc.supplyCap(), supplyCap);
        assertEq(sc.policyId(B20Constants.TRANSFER_SENDER_POLICY), PolicyRegistryConstants.ALWAYS_BLOCK_ID);
    }

    /// @notice Verifies deployB20 emits B20StablecoinDeployed with the correct parameters
    /// @dev Event integrity: all emitted fields must match the deploy arguments
    function test_deployB20_success_emitsB20StablecoinDeployed(bytes32 salt) public {
        address predicted = _computeB20Address(salt);
        vm.expectEmit(true, true, true, true);
        emit StablecoinFactory.B20StablecoinDeployed({
            stablecoin: predicted,
            name: TOKEN_NAME,
            symbol: TOKEN_SYMBOL,
            currency: TOKEN_CURRENCY,
            stablecoinAdmin: stablecoinAdmin,
            salt: salt
        });
        _deployB20(salt);
    }

    /// @notice Verifies the issued token address matches the address returned by computeB20Address
    /// @dev Determinism: the B-20 address must be predictable before issuance
    function test_deployB20_success_matchesComputedAddress(bytes32 salt) public {
        address predicted = _computeB20Address(salt);
        address issued = _deployB20(salt);
        assertEq(issued, predicted);
    }

    /// @notice Verifies the issued token carries the requested name, symbol, and currency, and fixed 6 decimals
    /// @dev Integration: the STABLECOIN create params must be forwarded to the precompile correctly
    function test_deployB20_success_initializesStablecoin(string calldata name, string calldata symbol) public {
        vm.prank(deployer);
        address token = factory.deployB20(name, symbol, TOKEN_CURRENCY, stablecoinAdmin, new bytes[](0), DEPLOY_SALT);
        IB20Stablecoin sc = IB20Stablecoin(token);
        assertEq(sc.name(), name);
        assertEq(sc.symbol(), symbol);
        assertEq(sc.currency(), TOKEN_CURRENCY);
        assertEq(sc.decimals(), 6);
    }

    /// @notice Verifies the issued token grants DEFAULT_ADMIN_ROLE to the specified stablecoinAdmin
    /// @dev Integration: the initialAdmin create param must be wired through to a role grant
    function test_deployB20_success_setsStablecoinAdmin(address stablecoinAdmin_, bytes32 salt) public {
        vm.assume(stablecoinAdmin_ != address(0));
        vm.prank(deployer);
        address token =
            factory.deployB20(TOKEN_NAME, TOKEN_SYMBOL, TOKEN_CURRENCY, stablecoinAdmin_, new bytes[](0), salt);
        IB20Stablecoin sc = IB20Stablecoin(token);
        assertTrue(sc.hasRole(sc.DEFAULT_ADMIN_ROLE(), stablecoinAdmin_));
    }

    // ── computeB20Address ─────────────────────────────────────────────────────────────────

    /// @notice Verifies computeB20Address returns different addresses for different salts
    /// @dev Determinism: distinct salts must produce distinct addresses
    function test_computeB20Address_success_deterministicForDistinctSalts(bytes32 salt1, bytes32 salt2) public view {
        vm.assume(salt1 != salt2);
        assertNotEq(_computeB20Address(salt1), _computeB20Address(salt2));
    }

    /// @notice Verifies computeB20Address is stable before and after issuance
    /// @dev Idempotent: calling computeB20Address before and after deployB20() must return the same address
    function test_computeB20Address_success_stableAcrossDeployment(bytes32 salt) public {
        address before = _computeB20Address(salt);
        address issued = _deployB20(salt);
        address after_ = _computeB20Address(salt);
        assertEq(before, issued);
        assertEq(before, after_);
    }
}
