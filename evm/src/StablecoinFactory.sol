// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.30;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";

/// @title StablecoinFactory
/// @notice UUPS-upgradeable factory that issues Base-native B-20 stablecoins via the canonical
/// {IB20Factory} precompile.
///
/// @dev The factory is a thin, access-controlled wrapper over the permissionless
/// {IB20Factory.createB20} entry point: it layers {DEPLOYER_ROLE} gating on top of the precompile
/// and encodes the STABLECOIN-variant creation params via {B20FactoryLib}. Issued tokens are native
/// B-20 STABLECOIN-variant tokens (fixed 6 decimals, immutable currency code); the factory holds no
/// role on them after creation.
/// @author Coinbase
///
/// Roles:
///   - DEFAULT_ADMIN_ROLE – can upgrade the factory and manage roles
///     (grant/revoke DEPLOYER_ROLE). Transfer is two-step with a configurable delay.
///   - DEPLOYER_ROLE – can issue new B-20 stablecoins via {deploy}.
contract StablecoinFactory is Initializable, AccessControlDefaultAdminRulesUpgradeable, UUPSUpgradeable {
    /// @notice Role required to issue new B-20 stablecoins via {deploy}.
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Emitted when a new B-20 stablecoin is issued.
    /// @param stablecoin      The address of the new stablecoin.
    /// @param name            The token name.
    /// @param symbol          The token symbol.
    /// @param currency        The immutable currency code (uppercase ASCII).
    /// @param stablecoinAdmin The initial default admin of the stablecoin.
    /// @param salt            The salt used for deterministic address derivation.
    event StablecoinDeployed(
        address indexed stablecoin,
        string name,
        string symbol,
        string currency,
        address indexed stablecoinAdmin,
        bytes32 indexed salt
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CONSTRUCTOR                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Disables initializers on the implementation.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     EXTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Initializes the factory with an admin, delay, and deployer.
    ///
    /// @param admin      Initial default admin (two-step transfer with delay).
    /// @param adminDelay Delay (in seconds) for admin transfer proposals.
    /// @param deployer   Address that can issue new stablecoins.
    function initialize(address admin, uint48 adminDelay, address deployer) external initializer {
        __AccessControlDefaultAdminRules_init({initialDelay: adminDelay, initialDefaultAdmin: admin});
        _grantRole({role: DEPLOYER_ROLE, account: deployer});
    }

    /// @notice Issues a new B-20 STABLECOIN-variant token via the {IB20Factory} precompile.
    ///
    /// @dev The token is created at the deterministic address derived from
    /// `(STABLECOIN, address(this), salt)`, so only this factory can issue tokens to the predicted
    /// addresses. `stablecoinAdmin` receives `DEFAULT_ADMIN_ROLE` on the new token; all other roles
    /// are granted by that admin post-issuance. Decimals are fixed at 6 by the STABLECOIN variant.
    ///
    /// @param name           Token name.
    /// @param symbol         Token symbol.
    /// @param currency       Immutable currency code; uppercase ASCII `A`-`Z` only.
    /// @param stablecoinAdmin The initial default admin of the stablecoin.
    /// @param salt           Salt for deterministic address derivation.
    ///
    /// @return stablecoin The address of the newly issued stablecoin.
    function deploy(
        string calldata name,
        string calldata symbol,
        string calldata currency,
        address stablecoinAdmin,
        bytes32 salt
    ) external onlyRole(DEPLOYER_ROLE) returns (address stablecoin) {
        bytes memory params = B20FactoryLib.encodeStablecoinCreateParams({
            name: name, symbol: symbol, initialAdmin: stablecoinAdmin, currency: currency
        });
        stablecoin = StdPrecompiles.B20_FACTORY
            .createB20({
                variant: IB20Factory.B20Variant.STABLECOIN, salt: salt, params: params, initCalls: new bytes[](0)
            });
        emit StablecoinDeployed({
            stablecoin: stablecoin,
            name: name,
            symbol: symbol,
            currency: currency,
            stablecoinAdmin: stablecoinAdmin,
            salt: salt
        });
    }

    /// @notice Returns the deterministic address a {deploy} with the given `salt` would assign,
    /// whether or not the token has been issued.
    ///
    /// @dev The address depends only on `(STABLECOIN, address(this), salt)` — not on the token's
    /// name, symbol, currency, or admin.
    ///
    /// @param salt The salt for deterministic address derivation.
    ///
    /// @return The deterministic stablecoin address.
    function computeAddress(bytes32 salt) external view returns (address) {
        return StdPrecompiles.B20_FACTORY.getB20Address(IB20Factory.B20Variant.STABLECOIN, address(this), salt);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     INTERNAL FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Restricts UUPS upgrades to the default admin.
    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
