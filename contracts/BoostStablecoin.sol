// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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

    function initialize(address admin_) external initializer {
        __ERC20_init("Boost", "BOOST");
        __ERC20Burnable_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function mint(address to_, uint256 amount_) public onlyRole(MINTER_ROLE) {
        _mint(to_, amount_);
    }

    function _beforeTokenTransfer(address from_, address to_, uint256 amount_) internal override whenNotPaused {
        super._beforeTokenTransfer(from_, to_, amount_);
    }
}
