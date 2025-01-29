// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libs/StakedUSDeLib.sol";
import "./libs/StakedFraxLib.sol";
import "./libs/SavingsDaiLib.sol";

contract PriceManagerQuoter {
    using StakedUSDeLib for StakedUSDeLib.StakedUSDe;
    using StakedFraxLib for StakedFraxLib.StakedFrax;
    using SavingsDaiLib for SavingsDaiLib.Pot;

    function sUsdePreviewRedeem(
        StakedUSDeLib.StakedUSDe calldata sUSDe,
        uint256 shares
    ) external view returns (uint256) {
        return sUSDe.previewRedeem(shares);
    }

    function sUsdePreviewDeposit(
        StakedUSDeLib.StakedUSDe calldata sUSDe,
        uint256 assets
    ) external view returns (uint256) {
        return sUSDe.previewDeposit(assets);
    }

    function sFraxPreviewRedeem(
        StakedFraxLib.StakedFrax calldata sFRAX,
        uint256 shares
    ) external view returns (uint256) {
        return sFRAX.previewRedeem(shares);
    }

    function sFraxPreviewDeposit(
        StakedFraxLib.StakedFrax calldata sFRAX,
        uint256 assets
    ) external view returns (uint256) {
        return sFRAX.previewDeposit(assets);
    }

    function sDaiPreviewRedeem(SavingsDaiLib.Pot calldata pot, uint256 shares) external view returns (uint256) {
        return pot.previewRedeem(shares);
    }

    function sDaiPreviewDeposit(SavingsDaiLib.Pot calldata pot, uint256 assets) external view returns (uint256) {
        return pot.previewDeposit(assets);
    }
}
