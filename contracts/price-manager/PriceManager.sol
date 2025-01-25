// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "./libs/StakedUSDeLib.sol";
import "./libs/StakedFraxLib.sol";
import "./libs/SavingsDaiLib.sol";
import "./muon/interfaces/IMuonClient.sol";

contract PriceManager is Initializable, AccessControlEnumerableUpgradeable {
    using StakedUSDeLib for StakedUSDeLib.StakedUSDe;
    using StakedFraxLib for StakedFraxLib.StakedFrax;
    using SavingsDaiLib for SavingsDaiLib.Pot;

    struct Block {
        uint256 number;
        uint256 timestamp;
    }

    struct MuonSig {
        Block srcBlock;
        bytes reqId;
        IMuonClient.SchnorrSign signature;
        bytes gatewaySignature;
    }

    bytes32 public constant SUSDE_SETTER = keccak256("SUSDE_SETTER");
    bytes32 public constant SFRAX_SETTER = keccak256("SFRAX_SETTER");
    bytes32 public constant SDAI_SETTER = keccak256("SDAI_SETTER");

    IMuonClient muonClient;
    StakedUSDeLib.StakedUSDe public sUSDe;
    Block public sUsdeLastBlock;
    StakedFraxLib.StakedFrax public sFRAX;
    Block public sFraxLastBlock;
    SavingsDaiLib.Pot public pot;
    Block public sDaiLastBlock;

    event SUsdeSet(StakedUSDeLib.StakedUSDe newStates, Block srcBlock);
    event SFraxSet(StakedFraxLib.StakedFrax newStates, Block srcBlock);
    event PotSet(SavingsDaiLib.Pot newStates, Block srcBlock);

    error ZeroAddress();
    error InvalidLastDistribution();
    error OldBlock(uint256 srcBlockTimestamp, uint256 lastBlockTimestamp);
    error InvalidBlock(uint256 srcBlockTimestamp, uint256 currentBlockTimestamp);

    function initialize(address admin, address setter) public onlyInitializing {
        __AccessControlEnumerable_init();

        if (admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        if (setter != address(0)) {
            _grantRole(SUSDE_SETTER, setter);
            _grantRole(SFRAX_SETTER, setter);
            _grantRole(SDAI_SETTER, setter);
        }
    }

    function _setSUsde(StakedUSDeLib.StakedUSDe calldata _sUSDe, Block calldata srcBlock) internal {
        if (srcBlock.timestamp > block.timestamp) revert InvalidBlock(srcBlock.timestamp, block.timestamp);
        if (srcBlock.timestamp <= sUsdeLastBlock.timestamp)
            revert OldBlock(srcBlock.timestamp, sUsdeLastBlock.timestamp);
        if (_sUSDe.lastDistributionTimestamp > block.timestamp) revert InvalidLastDistribution();
        sUSDe = _sUSDe;
        sUsdeLastBlock = srcBlock;
        emit SUsdeSet(_sUSDe, srcBlock);
    }

    function setSUsde(
        StakedUSDeLib.StakedUSDe calldata _sUSDe,
        Block calldata srcBlock
    ) external onlyRole(SUSDE_SETTER) {
        _setSUsde(_sUSDe, srcBlock);
    }

    function setSUsdeWithSig(StakedUSDeLib.StakedUSDe calldata _sUSDe, MuonSig calldata sig) external {
        bytes memory data = abi.encode(
            sig.srcBlock.number,
            sig.srcBlock.timestamp,
            _sUSDe.totalSupply,
            _sUSDe.balance,
            _sUSDe.lastDistributionTimestamp,
            _sUSDe.vestingAmount
        );
        muonClient.verifyTSSAndGW(data, sig.reqId, sig.signature, sig.gatewaySignature);
        _setSUsde(_sUSDe, sig.srcBlock);
    }

    function _setSFrax(StakedFraxLib.StakedFrax calldata _sFRAX, Block calldata srcBlock) internal {
        if (srcBlock.timestamp > block.timestamp) revert InvalidBlock(srcBlock.timestamp, block.timestamp);
        if (srcBlock.timestamp <= sFraxLastBlock.timestamp)
            revert OldBlock(srcBlock.timestamp, sFraxLastBlock.timestamp);
        if (_sFRAX.lastRewardsDistribution > block.timestamp) revert InvalidLastDistribution();
        sFRAX = _sFRAX;
        sFraxLastBlock = srcBlock;
        emit SFraxSet(_sFRAX, srcBlock);
    }

    function setSFrax(
        StakedFraxLib.StakedFrax calldata _sFRAX,
        Block calldata srcBlock
    ) external onlyRole(SFRAX_SETTER) {
        _setSFrax(_sFRAX, srcBlock);
    }

    function setSFraxWithSig(StakedFraxLib.StakedFrax calldata _sFRAX, MuonSig calldata sig) external {
        bytes memory data = abi.encode(
            sig.srcBlock.number,
            sig.srcBlock.timestamp,
            _sFRAX.totalSupply,
            _sFRAX.storedTotalAssets,
            _sFRAX.rewardsCycleData.cycleEnd,
            _sFRAX.rewardsCycleData.lastSync,
            _sFRAX.rewardsCycleData.rewardCycleAmount,
            _sFRAX.lastRewardsDistribution,
            _sFRAX.maxDistributionPerSecondPerAsset
        );
        muonClient.verifyTSSAndGW(data, sig.reqId, sig.signature, sig.gatewaySignature);
        _setSFrax(_sFRAX, sig.srcBlock);
    }

    function _setPot(SavingsDaiLib.Pot calldata _pot, Block calldata srcBlock) internal {
        if (srcBlock.timestamp > block.timestamp) revert InvalidBlock(srcBlock.timestamp, block.timestamp);
        if (srcBlock.timestamp <= sDaiLastBlock.timestamp) revert OldBlock(srcBlock.timestamp, sDaiLastBlock.timestamp);
        if (_pot.rho > block.timestamp) revert InvalidLastDistribution();
        pot = _pot;
        emit PotSet(_pot, srcBlock);
    }

    function setPot(SavingsDaiLib.Pot calldata _pot, Block calldata srcBlock) external onlyRole(SDAI_SETTER) {
        _setPot(_pot, srcBlock);
    }

    function setSPotWithSig(SavingsDaiLib.Pot calldata _pot, MuonSig calldata sig) external {
        bytes memory data = abi.encode(sig.srcBlock.number, sig.srcBlock.timestamp, _pot.dsr, _pot.chi, _pot.rho);
        muonClient.verifyTSSAndGW(data, sig.reqId, sig.signature, sig.gatewaySignature);
        _setPot(_pot, sig.srcBlock);
    }

    function sUsdePreviewRedeem(uint256 shares) external view returns (uint256) {
        return sUSDe.previewRedeem(shares);
    }

    function sUsdePreviewDeposit(uint256 assets) external view returns (uint256) {
        return sUSDe.previewDeposit(assets);
    }

    function sFraxPreviewRedeem(uint256 shares) external view returns (uint256) {
        return sFRAX.previewRedeem(shares);
    }

    function sFraxPreviewDeposit(uint256 assets) external view returns (uint256) {
        return sFRAX.previewDeposit(assets);
    }

    function sDaiPreviewRedeem(uint256 shares) external view returns (uint256) {
        return pot.previewRedeem(shares);
    }

    function sDaiPreviewDeposit(uint256 assets) external view returns (uint256) {
        return pot.previewDeposit(assets);
    }
}
