// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";

contract Minter is Initializable, AccessControlEnumerableUpgradeable, PausableUpgradeable, IMinter {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public boostAddress;
    address public collateralAddress;
    address public treasury;
    uint256 public collateralDecimals;

    bytes32 public constant WITHDRAW_TOKEN_ROLE = keccak256("WITHDRAW_TOKEN_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AMO_ROLE = keccak256("AMO_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address boostAddress_, address collateralAddress_, address treasury_) external initializer {
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        require(boostAddress_ != address(0), "Zero address NOT allowed");
        require(treasury_ != address(0), "Zero address NOT allowed");
        treasury = treasury_;
        boostAddress = boostAddress_;
        collateralAddress = collateralAddress_;
        collateralDecimals = IERC20Metadata(collateralAddress).decimals();
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    function setTokens(address boostAddress_, address collateralAddress_) public onlyRole(ADMIN_ROLE) {
        require(boostAddress_ != address(0), "Zero address NOT allowed");
        boostAddress = boostAddress_;
        collateralAddress = collateralAddress_;
        collateralDecimals = IERC20Metadata(collateralAddress).decimals();
        emit TokensAddressesUpdated(boostAddress_, collateralAddress_);
    }

    function setTreasury(address treasury_) public onlyRole(ADMIN_ROLE) {
        require(treasury_ != address(0), "Zero address NOT allowed");
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function mint(address to_, uint256 amount_) external whenNotPaused onlyRole(MINTER_ROLE) {
        IERC20Upgradeable(collateralAddress).safeTransferFrom(
            msg.sender,
            treasury,
            amount_ / (10 ** (18 - collateralDecimals))
        );

        IBoostStablecoin(boostAddress).mint(to_, amount_);

        emit TokenMinted(msg.sender, to_, amount_);
    }

    function protocolMint(address to_, uint256 amount_) external whenNotPaused onlyRole(AMO_ROLE) {
        IBoostStablecoin(boostAddress).mint(to_, amount_);
        emit TokenProtocolMinted(msg.sender, to_, amount_);
    }

    function withdrawToken(address token_, uint256 amount_) external onlyRole(WITHDRAW_TOKEN_ROLE) {
        IERC20Upgradeable(token_).safeTransfer(treasury, amount_);
        emit TokenWithdrawn(token_, amount_);
    }
}
