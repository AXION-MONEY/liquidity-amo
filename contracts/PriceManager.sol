// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "./libs/StakedUSDeLib.sol";
import "./libs/StakedFraxLib.sol";
import "./libs/SavingsDaiLib.sol";

contract PriceManager is Initializable, AccessControlEnumerableUpgradeable {
    using StakedUSDeLib for StakedUSDeLib.StakedUSDe;
    using StakedFraxLib for StakedFraxLib.StakedFrax;
    using SavingsDaiLib for SavingsDaiLib.Pot;

    bytes32 public constant SUSDE_SETTER = keccak256("SUSDE_SETTER");
    bytes32 public constant SFRAX_SETTER = keccak256("SFRAX_SETTER");
    bytes32 public constant SDAI_SETTER = keccak256("SDAI_SETTER");

    StakedUSDeLib.StakedUSDe public sUSDe;
    uint256 public sUsdeLastSync;
    StakedFraxLib.StakedFrax public sFRAX;
    uint256 public sFraxLastSync;
    SavingsDaiLib.Pot public pot;
    uint256 public sDaiLastSync;

    error ZeroAddress();
    error InvalidLastDistribution();

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

    function setSUsde(StakedUSDeLib.StakedUSDe calldata _sUSDe) external onlyRole(SUSDE_SETTER) {
        if (_sUSDe.lastDistributionTimestamp > block.timestamp) revert InvalidLastDistribution();
        sUSDe = _sUSDe;
        sUsdeLastSync = block.timestamp;
    }

    function setSFrax(StakedFraxLib.StakedFrax calldata _sFRAX) external onlyRole(SFRAX_SETTER) {
        if (_sFRAX.lastRewardsDistribution > block.timestamp) revert InvalidLastDistribution();
        sFRAX = _sFRAX;
        sFraxLastSync = block.timestamp;
    }

    function setPot(SavingsDaiLib.Pot calldata _pot) external onlyRole(SDAI_SETTER) {
        pot = _pot;
        sDaiLastSync = block.timestamp;
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
