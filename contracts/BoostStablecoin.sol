// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;


import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * the Boost coin itself is upgradable but behind a time lock.
 * in future versions, will will upgrade the pause/unpause process to maximise security while giving decentralisation guarantees
     + BOOST will be pausable for security
     + BOOST will also be team-unpausable (after possible timelock)
     + Governance votes will be able to force unpause ( with further timelock for new pause) to stick to decentralisation ethos
 * these clever control features will require further upgrades — the Boost coin itself will be upgradable ( subject to proof-validation )
 * overall we strive to achieve both security and decentralisation:  we can pause the contracts as most stables can nowadays; still we will guarantee that pause is censorship resistant!
 **/

contract BoostStablecoin is
    Initializable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    AccessControlEnumerableUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        __ERC20_init("Boost", "BOOST");
        __ERC20Burnable_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 amount) internal override whenNotPaused {
        super._update(from, to, amount);
    }

}
