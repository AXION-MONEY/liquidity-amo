// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";

/**
 * @title BoostStablecoin
 * @notice The Boost stablecoin is upgradable and pausable. It is designed with role-based control
 *         to allow security features such as pausing in emergencies and controlled minting.
 * @dev Inherits from Initializable, ERC20BurnableUpgradeable, PausableUpgradeable, and AccessControlEnumerableUpgradeable;
 *      implements IBoostStablecoin.
 */
contract BoostStablecoin is
    Initializable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    IBoostStablecoin
{
    // -------------------------------------------------------------
    //                         STATE VARIABLES
    // -------------------------------------------------------------
    // (No additional state variables; token data is inherited from ERC20)

    // -------------------------------------------------------------
    //                             ROLES
    // -------------------------------------------------------------
    /// @inheritdoc IBoostStablecoin
    bytes32 public constant override MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @inheritdoc IBoostStablecoin
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @inheritdoc IBoostStablecoin
    bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    // -------------------------------------------------------------
    //                        INITIALIZATION
    // -------------------------------------------------------------
    /**
     * @notice Constructor disables initializers.
     * @dev Required for upgradeable contracts.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the BoostStablecoin contract.
     * @param admin The address to be granted the DEFAULT_ADMIN_ROLE.
     */
    function initialize(address admin) external initializer {
        __ERC20_init("Boost", "BOOST");
        __ERC20Burnable_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // -------------------------------------------------------------
    //                   PAUSE/UNPAUSE FUNCTIONS
    // -------------------------------------------------------------
    /**
     * @notice Pauses the contract.
     * @dev Callable only by accounts with the PAUSER_ROLE.
     */
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev Callable only by accounts with the UNPAUSER_ROLE.
     */
    function unpause() public onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------
    //                      MINTER FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IBoostStablecoin
    function mint(address to, uint256 amount) public override onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // -------------------------------------------------------------
    //               OVERRIDES FOR ERC20BurnableUpgradeable
    // -------------------------------------------------------------

    /// @inheritdoc IBoostStablecoin
    function burn(uint256 value) public override(ERC20BurnableUpgradeable, IBoostStablecoin) {
        super.burn(value);
    }

     /// @inheritdoc IBoostStablecoin
    function burnFrom(address account, uint256 value) public override(ERC20BurnableUpgradeable, IBoostStablecoin) {
        super.burnFrom(account, value);
    }

    // -------------------------------------------------------------
    //                    INTERNAL OVERRIDES
    // -------------------------------------------------------------
    /**
     * @notice Overrides the internal _update function to require that transfers occur only when not paused.
     * @param from The address sending tokens.
     * @param to The address receiving tokens.
     * @param amount The token amount being transferred.
     * @dev Calls the parent implementation after checking the pause condition.
     */
    function _update(address from, address to, uint256 amount) internal override whenNotPaused {
        super._update(from, to, amount);
    }
}
