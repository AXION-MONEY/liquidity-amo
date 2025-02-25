// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import "./interfaces/IPriceManager.sol";
import "./libs/StakedUSDeLib.sol";
import "./libs/StakedFraxLib.sol";
import "./libs/SavingsDaiLib.sol";
import "./muon/interfaces/IMuonClient.sol";

/**
 * @title PriceManager
 * @notice Manages price state updates for staked assets using off-chain (MUON) signature verification.
 * @dev Uses an upgradeable pattern with role-based access control.
 */
contract PriceManager is IPriceManager, Initializable, AccessControlEnumerableUpgradeable {
    using StakedUSDeLib for StakedUSDeLib.StakedUSDe;
    using StakedFraxLib for StakedFraxLib.StakedFrax;
    using SavingsDaiLib for SavingsDaiLib.Pot;

    // -------------------------------------------------------------
    //                        ROLES & CONSTANTS
    // -------------------------------------------------------------
    /// @inheritdoc IPriceManager
    bytes32 public constant TOKEN_UPDATER_ROLE = keccak256("TOKEN_UPDATER_ROLE");
    /// @inheritdoc IPriceManager
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    // -------------------------------------------------------------
    //                       STATE VARIABLES
    // -------------------------------------------------------------
    /// @notice Instance of the Muon Client for signature verification.
    IMuonClient public muonClient;

    /// @notice Current state of staked USDe.
    StakedUSDeLib.StakedUSDe public sUSDe;
    /// @notice The block data corresponding to the last update of sUSDe.
    Block public sUsdeLastBlock;

    /// @notice Current state of staked FRAX.
    StakedFraxLib.StakedFrax public sFRAX;
    /// @notice The block data corresponding to the last update of sFRAX.
    Block public sFraxLastBlock;

    /// @notice Current state of the Savings DAI pot.
    SavingsDaiLib.Pot public pot;
    /// @notice The block data corresponding to the last update of the Savings DAI pot.
    Block public sDaiLastBlock;

    // -------------------------------------------------------------
    //                      INITIALIZATION
    // -------------------------------------------------------------
    /**
     * @notice Initializes the PriceManager contract.
     * @param admin The address to be granted the DEFAULT_ADMIN_ROLE.
     * @param tokenUpdater The address to be granted the TOKEN_UPDATER_ROLE.
     * @param setter The address to be granted the SETTER_ROLE.
     * @param muonClientAddress The address of the Muon client contract.
     */
    function initialize(
        address admin,
        address tokenUpdater,
        address setter,
        address muonClientAddress
    ) public initializer {
        __AccessControlEnumerable_init();

        if (
            admin == address(0) || muonClientAddress == address(0) || setter == address(0) || tokenUpdater == address(0)
        ) revert ZeroAddress();

        // Temporarily grant SETTER_ROLE to msg.sender for initialization
        _grantRole(SETTER_ROLE, msg.sender);
        setMuonClient(muonClientAddress);
        _revokeRole(SETTER_ROLE, msg.sender);

        _grantRole(TOKEN_UPDATER_ROLE, tokenUpdater);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SETTER_ROLE, setter);
    }

    // -------------------------------------------------------------
    //                      INTERNAL FUNCTIONS
    // -------------------------------------------------------------
    /**
     * @notice Validates that the source block timestamp is acceptable.
     * @dev Ensures the source block timestamp is not in the future and is newer than the last update.
     * @param srcTimestamp The timestamp from the signed source block.
     * @param lastTimestamp The timestamp of the last processed block.
     */
    function _validateSrcBlock(uint256 srcTimestamp, uint256 lastTimestamp) internal view {
        if (srcTimestamp > block.timestamp) {
            revert InvalidBlock(srcTimestamp, block.timestamp);
        }
        if (srcTimestamp <= lastTimestamp) {
            revert OldBlock(srcTimestamp, lastTimestamp);
        }
    }

    /**
     * @notice Internal function to update the state of sUSDe.
     * @param _sUSDe The new sUSDe state.
     * @param srcBlock The block reference associated with the update.
     */
    function _setSUsde(StakedUSDeLib.StakedUSDe calldata _sUSDe, Block calldata srcBlock) internal {
        _validateSrcBlock(srcBlock.timestamp, sUsdeLastBlock.timestamp);
        if (_sUSDe.lastDistributionTimestamp > block.timestamp) revert InvalidLastDistribution();

        sUSDe = _sUSDe;
        sUsdeLastBlock = srcBlock;
        emit SUsdeSet(_sUSDe, srcBlock);
    }

    /**
     * @notice Internal function to update the state of sFRAX.
     * @param _sFRAX The new sFRAX state.
     * @param srcBlock The block reference associated with the update.
     */
    function _setSFrax(StakedFraxLib.StakedFrax calldata _sFRAX, Block calldata srcBlock) internal {
        _validateSrcBlock(srcBlock.timestamp, sFraxLastBlock.timestamp);
        if (_sFRAX.lastRewardsDistribution > block.timestamp) revert InvalidLastDistribution();

        sFRAX = _sFRAX;
        sFraxLastBlock = srcBlock;
        emit SFraxSet(_sFRAX, srcBlock);
    }

    /**
     * @notice Internal function to update the state of the Savings DAI pot.
     * @param _pot The new Savings DAI pot state.
     * @param srcBlock The block reference associated with the update.
     */
    function _setPot(SavingsDaiLib.Pot calldata _pot, Block calldata srcBlock) internal {
        _validateSrcBlock(srcBlock.timestamp, sDaiLastBlock.timestamp);
        if (_pot.rho > block.timestamp) revert InvalidLastDistribution();

        pot = _pot;
        sDaiLastBlock = srcBlock;
        emit PotSet(_pot, srcBlock);
    }

    // -------------------------------------------------------------
    //                     EXTERNAL FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IPriceManager
    function setMuonClient(address _muonClientAddress) public onlyRole(SETTER_ROLE) {
        muonClient = IMuonClient(_muonClientAddress);
        emit SetMuonClient(_muonClientAddress);
    }

    ////// SUsde SET Price Values FUNCTIONS //////

    /// @inheritdoc IPriceManager
    function setSUsde(
        StakedUSDeLib.StakedUSDe calldata _sUSDe,
        Block calldata srcBlock
    ) external onlyRole(TOKEN_UPDATER_ROLE) {
        _setSUsde(_sUSDe, srcBlock);
    }

    /// @inheritdoc IPriceManager
    function setSUsdeWithSig(StakedUSDeLib.StakedUSDe calldata _sUSDe, MuonSig calldata sig) external {
        if (keccak256(bytes(sig.token)) != keccak256("susde")) revert SigTokenMismatch();
        bytes memory data = abi.encodePacked(
            sig.srcBlock.number,
            sig.srcBlock.timestamp,
            _sUSDe.totalSupply,
            _sUSDe.balance,
            _sUSDe.lastDistributionTimestamp,
            _sUSDe.vestingAmount,
            sig.token
        );
        muonClient.verifyTSSAndGW(data, sig.reqId, sig.signature, sig.gatewaySignature);
        _setSUsde(_sUSDe, sig.srcBlock);
    }

    ////// SFRAX SET Price Values FUNCTIONS //////

    /// @inheritdoc IPriceManager
    function setSFrax(
        StakedFraxLib.StakedFrax calldata _sFRAX,
        Block calldata srcBlock
    ) external onlyRole(TOKEN_UPDATER_ROLE) {
        _setSFrax(_sFRAX, srcBlock);
    }

    /// @inheritdoc IPriceManager
    function setSFraxWithSig(StakedFraxLib.StakedFrax calldata _sFRAX, MuonSig calldata sig) external {
        if (keccak256(bytes(sig.token)) != keccak256("sfrax")) revert SigTokenMismatch();
        bytes memory data = abi.encodePacked(
            sig.srcBlock.number,
            sig.srcBlock.timestamp,
            _sFRAX.totalSupply,
            _sFRAX.storedTotalAssets,
            _sFRAX.rewardsCycleData.cycleEnd,
            _sFRAX.rewardsCycleData.lastSync,
            _sFRAX.rewardsCycleData.rewardCycleAmount,
            _sFRAX.lastRewardsDistribution,
            _sFRAX.maxDistributionPerSecondPerAsset,
            sig.token
        );
        muonClient.verifyTSSAndGW(data, sig.reqId, sig.signature, sig.gatewaySignature);
        _setSFrax(_sFRAX, sig.srcBlock);
    }

    ////// SDAI SET Price Values FUNCTIONS //////

    /// @inheritdoc IPriceManager
    function setPot(SavingsDaiLib.Pot calldata _pot, Block calldata srcBlock) external onlyRole(TOKEN_UPDATER_ROLE) {
        _setPot(_pot, srcBlock);
    }

    /// @inheritdoc IPriceManager
    function setPotWithSig(SavingsDaiLib.Pot calldata _pot, MuonSig calldata sig) external {
        if (keccak256(bytes(sig.token)) != keccak256("sdai")) revert SigTokenMismatch();
        bytes memory data = abi.encodePacked(
            sig.srcBlock.number,
            sig.srcBlock.timestamp,
            _pot.dsr,
            _pot.chi,
            _pot.rho,
            sig.token
        );
        muonClient.verifyTSSAndGW(data, sig.reqId, sig.signature, sig.gatewaySignature);
        _setPot(_pot, sig.srcBlock);
    }

    // -------------------------------------------------------------
    //                      VIEW FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IPriceManager
    function sUsdePreviewRedeem(uint256 shares) external view returns (uint256) {
        return sUSDe.previewRedeem(shares);
    }

    /// @inheritdoc IPriceManager
    function sUsdePreviewDeposit(uint256 assets) external view returns (uint256) {
        return sUSDe.previewDeposit(assets);
    }

    /// @inheritdoc IPriceManager
    function sFraxPreviewRedeem(uint256 shares) external view returns (uint256) {
        return sFRAX.previewRedeem(shares);
    }

    /// @inheritdoc IPriceManager
    function sFraxPreviewDeposit(uint256 assets) external view returns (uint256) {
        return sFRAX.previewDeposit(assets);
    }

    /// @inheritdoc IPriceManager
    function sDaiPreviewRedeem(uint256 shares) external view returns (uint256) {
        return pot.previewRedeem(shares);
    }

    /// @inheritdoc IPriceManager
    function sDaiPreviewDeposit(uint256 assets) external view returns (uint256) {
        return pot.previewDeposit(assets);
    }
}
