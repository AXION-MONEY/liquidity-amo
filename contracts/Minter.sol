// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IIon} from "./interfaces/IIon.sol";

/**
 * @title Minter Contract
 * @notice Implements minting, protocol minting, and token withdrawal operations.
 * @dev Inherits from Initializable, AccessControlEnumerableUpgradeable, and PausableUpgradeable; implements IMinter.
 */
contract Minter is Initializable, AccessControlEnumerableUpgradeable, PausableUpgradeable, IMinter {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------
    //                         STATE VARIABLES
    // -------------------------------------------------------------
    /// @inheritdoc IMinter
    address public override ionAddress;
    /// @inheritdoc IMinter
    address public override collateralAddress;
    /// @inheritdoc IMinter
    address public override treasury;
    /// @inheritdoc IMinter
    uint8 public override ionDecimals;
    /// @inheritdoc IMinter
    uint8 public override collateralDecimals;

    // -------------------------------------------------------------
    //                             ROLES
    // -------------------------------------------------------------
    /// @inheritdoc IMinter
    bytes32 public constant override MINTER_ROLE = keccak256("MINTER_ROLE");
    /// @inheritdoc IMinter
    bytes32 public constant override ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @inheritdoc IMinter
    bytes32 public constant override AMO_ROLE = keccak256("AMO_ROLE");
    /// @inheritdoc IMinter
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @inheritdoc IMinter
    bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    /// @inheritdoc IMinter
    bytes32 public constant override WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    // -------------------------------------------------------------
    //                          MODIFIERS
    // -------------------------------------------------------------
    modifier onlyContract() {
        if (msg.sender.code.length == 0) revert NonContractSender();
        _;
    }

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
     * @notice Initializes the Minter contract.
     * @param ionAddress_ The ION token address.
     * @param collateralAddress_ The collateral token address.
     * @param treasury_ The treasury address.
     */
    function initialize(address ionAddress_, address collateralAddress_, address treasury_) external initializer {
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (ionAddress_ == address(0) || collateralAddress_ == address(0) || treasury_ == address(0))
            revert ZeroAddress();
        ionAddress = ionAddress_;
        collateralAddress = collateralAddress_;
        treasury = treasury_;
        ionDecimals = IERC20Metadata(ionAddress).decimals();
        collateralDecimals = IERC20Metadata(collateralAddress).decimals();
    }

    // -------------------------------------------------------------
    //                   PAUSE/UNPAUSE FUNCTIONS
    // -------------------------------------------------------------
    /// @inheritdoc IMinter
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IMinter
    function unpause() external override onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------
    //                      ADMIN FUNCTIONS
    // -------------------------------------------------------------
    /// @inheritdoc IMinter
    function setTokens(address ionAddress_, address collateralAddress_) external override onlyRole(ADMIN_ROLE) {
        if (ionAddress_ == address(0) || collateralAddress_ == address(0)) revert ZeroAddress();
        ionAddress = ionAddress_;
        collateralAddress = collateralAddress_;
        ionDecimals = IERC20Metadata(ionAddress).decimals();
        collateralDecimals = IERC20Metadata(collateralAddress).decimals();
        emit TokenAddressesUpdated(ionAddress_, collateralAddress_);
    }

    /// @inheritdoc IMinter
    function setTreasury(address treasury_) external override onlyRole(ADMIN_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    // -------------------------------------------------------------
    //                      MINTER FUNCTIONS
    // -------------------------------------------------------------
    /// @inheritdoc IMinter
    function mint(address to, uint256 amount) external override whenNotPaused onlyContract onlyRole(MINTER_ROLE) {
        IERC20(collateralAddress).safeTransferFrom(
            msg.sender,
            treasury,
            amount / (10 ** (ionDecimals - collateralDecimals))
        );
        IIon(ionAddress).mint(to, amount);
        emit TokenMinted(msg.sender, to, amount);
    }

    /// @inheritdoc IMinter
    function protocolMint(address to, uint256 amount) external override whenNotPaused onlyContract onlyRole(AMO_ROLE) {
        IIon(ionAddress).mint(to, amount);
        emit TokenProtocolMinted(msg.sender, to, amount);
    }

    /// @inheritdoc IMinter
    function withdrawToken(address token, uint256 amount) external override onlyRole(WITHDRAWER_ROLE) {
        IERC20(token).safeTransfer(treasury, amount);
        emit TokenWithdrawn(token, amount);
    }
}
