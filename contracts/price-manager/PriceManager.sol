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
 * @notice The contract Also provides RoleBased Function to update price for risk management if MUON can't provide sigs
 * @dev Uses upgradeable pattern with role-based access control.
 */
contract PriceManager is IPriceManager, Initializable, AccessControlEnumerableUpgradeable {
    using StakedUSDeLib for StakedUSDeLib.StakedUSDe;
    using StakedFraxLib for StakedFraxLib.StakedFrax;
    using SavingsDaiLib for SavingsDaiLib.Pot;

    /// @notice Structure representing a block reference.
    struct Block {
        uint256 number;
        uint256 timestamp;
    }

    /// @notice Structure representing a Muon signature payload.
    struct MuonSig {
        Block srcBlock;
        bytes reqId;
        IMuonClient.SchnorrSign signature;
        bytes gatewaySignature;
        string token;
    }

    // Roles for updating asset states.
    bytes32 public constant TOKEN_UPDATER_ROLE = keccak256("TOKEN_UPDATER_ROLE");

    // Roles to set Configs
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

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

    // =============================================================
    //                           EVENTS
    // =============================================================
    event SetMuonClient(address muonClientAddress);
    event SUsdeSet(StakedUSDeLib.StakedUSDe newStates, Block srcBlock);
    event SFraxSet(StakedFraxLib.StakedFrax newStates, Block srcBlock);
    event PotSet(SavingsDaiLib.Pot newStates, Block srcBlock);

    // =============================================================
    //                           CUSTOM ERRORS
    // =============================================================
    error ZeroAddress();
    error InvalidLastDistribution();
    error OldBlock(uint256 srcBlockTimestamp, uint256 lastBlockTimestamp);
    error InvalidBlock(uint256 srcBlockTimestamp, uint256 currentBlockTimestamp);
    error SigTokenMismatch();

    /**
     * @notice Initializes the contract with an admin, a setter, and the Muon client address.
     * @param admin The address to be granted DEFAULT_ADMIN_ROLE.
     * @param token_updater The address to be granted TOKEN_UPDATER.
     * @param setter The address to be granted asset setter roles.
     * @param muonClientAddress The address of the Muon client contract.
     */
    function initialize(
        address admin,
        address token_updater,
        address setter,
        address muonClientAddress
    ) public initializer {
        __AccessControlEnumerable_init();

        if (admin == address(0) || muonClient == address(0) || setter == address(0) || token_updater == address(0))
            revert ZeroAddress();

        _grantRole(SETTER_ROLE, msg.sender);
        setMuonClient(muonClientAddress);
        _revokeRole(SETTER_ROLE, msg.sender);

        _grantRole(TOKEN_UPDATER_ROLE, token_updater);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SETTER_ROLE, setter);
    }

    /**
     * @notice setMuonClient initiate (re-initiate) muonClient.
     * @dev Can be called Only by SETTER ROLE.
     * @param _muonClientAddress the address of the muonClient.
     */
    function setMuonClient(address _muonClientAddress) public onlyRole(SETTER_ROLE) {
        muonClient = IMuonClient(_muonClientAddress);
        emit SetMuonClient(_muonClientAddress);
    }

    // =============================================================
    //                           SUSDE FUNCTIONS
    // =============================================================

    /**
     * @notice Internal function to update the state of sUSDe.
     * @param _sUSDe The new sUSDe state.
     * @param srcBlock The block reference associated with the update.
     */
    function _setSUsde(StakedUSDeLib.StakedUSDe calldata _sUSDe, Block calldata srcBlock) internal {
        // srcBlock.timestamp is not in the future
        if (srcBlock.timestamp > block.timestamp) revert InvalidBlock(srcBlock.timestamp, block.timestamp);
        // srcBlock.timestamp is newer than the previous timestamp
        if (srcBlock.timestamp <= sUsdeLastBlock.timestamp)
            revert OldBlock(srcBlock.timestamp, sUsdeLastBlock.timestamp);
        // lastDistributionTimestamp is not in the future
        if (_sUSDe.lastDistributionTimestamp > block.timestamp) revert InvalidLastDistribution();

        // update corresponding asset values
        sUSDe = _sUSDe;
        sUsdeLastBlock = srcBlock;

        emit SUsdeSet(_sUSDe, srcBlock);
    }

    /**
     * @notice Updates sUSDe state. Callable only by addresses with the TOKEN_UPDATER_ROLE role.
     * @param _sUSDe The new sUSDe state.
     * @param srcBlock The block reference associated with the update.
     */
    function setSUsde(
        StakedUSDeLib.StakedUSDe calldata _sUSDe,
        Block calldata srcBlock
    ) external onlyRole(TOKEN_UPDATER_ROLE) {
        _setSUsde(_sUSDe, srcBlock);
    }

    /**
     * @notice Updates sUSDe state using off-chain signature verification.
     * @param _sUSDe The new sUSDe state.
     * @param sig The Muon signature payload.
     */
    function setSUsdeWithSig(StakedUSDeLib.StakedUSDe calldata _sUSDe, MuonSig calldata sig) external {
        // Verify that the token in the signature is exactly "susde"
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

        // Verify MUON sig
        muonClient.verifyTSSAndGW(data, sig.reqId, sig.signature, sig.gatewaySignature);

        _setSUsde(_sUSDe, sig.srcBlock);
    }

    // =============================================================
    //                           SFRAX FUNCTIONS
    // =============================================================

    /**
     * @notice Internal function to update the state of sFRAX.
     * @param _sFRAX The new sFRAX state.
     * @param srcBlock The block reference associated with the update.
     */
    function _setSFrax(StakedFraxLib.StakedFrax calldata _sFRAX, Block calldata srcBlock) internal {
        // srcBlock.timestamp is not in the future
        if (srcBlock.timestamp > block.timestamp) revert InvalidBlock(srcBlock.timestamp, block.timestamp);
        // srcBlock.timestamp is newer than the previous timestamp
        if (srcBlock.timestamp <= sFraxLastBlock.timestamp)
            revert OldBlock(srcBlock.timestamp, sFraxLastBlock.timestamp);
        // lastDistributionTimestamp is not in the future
        if (_sFRAX.lastRewardsDistribution > block.timestamp) revert InvalidLastDistribution();

        sFRAX = _sFRAX;
        sFraxLastBlock = srcBlock;

        emit SFraxSet(_sFRAX, srcBlock);
    }

    /**
     * @notice Updates sFRAX state. Callable only by addresses with the TOKEN_UPDATER_ROLE role.
     * @param _sFRAX The new sFRAX state.
     * @param srcBlock The block reference associated with the update.
     */
    function setSFrax(
        StakedFraxLib.StakedFrax calldata _sFRAX,
        Block calldata srcBlock
    ) external onlyRole(TOKEN_UPDATER_ROLE) {
        _setSFrax(_sFRAX, srcBlock);
    }

    /**
     * @notice Updates sFRAX state using off-chain signature verification.
     * @param _sFRAX The new sFRAX state.
     * @param sig The Muon signature payload.
     */
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

    // =============================================================
    //                           SDAI FUNCTIONS
    // =============================================================

    /**
     * @notice Internal function to update the Savings DAI pot state.
     * @param _pot The new Savings DAI pot state.
     * @param srcBlock The block reference associated with the update.
     */
    function _setPot(SavingsDaiLib.Pot calldata _pot, Block calldata srcBlock) internal {
        // checking times to valid not in the future and also is newer than the previous timestamp
        if (srcBlock.timestamp > block.timestamp) revert InvalidBlock(srcBlock.timestamp, block.timestamp);
        if (srcBlock.timestamp <= sDaiLastBlock.timestamp) revert OldBlock(srcBlock.timestamp, sDaiLastBlock.timestamp);
        if (_pot.rho > block.timestamp) revert InvalidLastDistribution();

        pot = _pot;
        sDaiLastBlock = srcBlock;

        emit PotSet(_pot, srcBlock);
    }

    /**
     * @notice Updates the Savings DAI pot state. Callable only by addresses with the TOKEN_UPDATER_ROLE role.
     * @param _pot The new Savings DAI pot state.
     * @param srcBlock The block reference associated with the update.
     */
    function setPot(SavingsDaiLib.Pot calldata _pot, Block calldata srcBlock) external onlyRole(TOKEN_UPDATER_ROLE) {
        _setPot(_pot, srcBlock);
    }

    /**
     * @notice Updates the Savings DAI pot state using off-chain signature verification.
     * @param _pot The new Savings DAI pot state.
     * @param sig The Muon signature payload.
     */
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

    // =============================================================
    //                           VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Returns the underlying assets that would be redeemed for a given amount of sUSDe shares.
     * @param shares The number of sUSDe shares.
     * @return The amount of underlying assets.
     */
    function sUsdePreviewRedeem(uint256 shares) external view returns (uint256) {
        return sUSDe.previewRedeem(shares);
    }

    /**
     * @notice Returns the number of sUSDe shares that would be minted for a given asset deposit.
     * @param assets The amount of assets to deposit.
     * @return The amount of sUSDe shares.
     */
    function sUsdePreviewDeposit(uint256 assets) external view returns (uint256) {
        return sUSDe.previewDeposit(assets);
    }

    /**
     * @notice Returns the underlying assets that would be redeemed for a given amount of sFRAX shares.
     * @param shares The number of sFRAX shares.
     * @return The amount of underlying assets.
     */
    function sFraxPreviewRedeem(uint256 shares) external view returns (uint256) {
        return sFRAX.previewRedeem(shares);
    }

    /**
     * @notice Returns the number of sFRAX shares that would be minted for a given asset deposit.
     * @param assets The amount of assets to deposit.
     * @return The amount of sFRAX shares.
     */
    function sFraxPreviewDeposit(uint256 assets) external view returns (uint256) {
        return sFRAX.previewDeposit(assets);
    }

    /**
     * @notice Returns the underlying assets that would be redeemed for a given amount of Savings DAI shares.
     * @param shares The number of Savings DAI shares.
     * @return The amount of underlying assets.
     */
    function sDaiPreviewRedeem(uint256 shares) external view returns (uint256) {
        return pot.previewRedeem(shares);
    }

    /**
     * @notice Returns the number of Savings DAI shares that would be minted for a given asset deposit.
     * @param assets The amount of assets to deposit.
     * @return The amount of Savings DAI shares.
     */
    function sDaiPreviewDeposit(uint256 assets) external view returns (uint256) {
        return pot.previewDeposit(assets);
    }
}
