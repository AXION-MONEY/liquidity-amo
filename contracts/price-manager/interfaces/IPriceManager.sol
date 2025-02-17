// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceManager {

    // =============================================================
    //                           VIEW FUNCTIONS
    // =============================================================

    function sUsdePreviewRedeem(uint256 shares) external view returns (uint256 assets);

    function sUsdePreviewDeposit(uint256 assets) external view returns (uint256 shares);

    function sFraxPreviewRedeem(uint256 shares) external view returns (uint256 assets);

    function sFraxPreviewDeposit(uint256 assets) external view returns (uint256 shares);

    function sDaiPreviewRedeem(uint256 shares) external view returns (uint256 assets);

    function sDaiPreviewDeposit(uint256 assets) external view returns (uint256 shares);
}
