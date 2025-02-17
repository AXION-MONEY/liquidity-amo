// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./libs/StakedUSDeLib.sol";
import "./libs/StakedFraxLib.sol";
import "./libs/SavingsDaiLib.sol";

/**
 * @title PriceManagerQuoter
 * @notice Provides pure preview functions for asset deposit and redemption calculations.
 */
contract PriceManagerQuoter {
    using StakedUSDeLib for StakedUSDeLib.StakedUSDe;
    using StakedFraxLib for StakedFraxLib.StakedFrax;
    using SavingsDaiLib for SavingsDaiLib.Pot;

    /**
     * @notice Returns the underlying assets that would be redeemed for a given amount of sUSDe shares.
     * @param sUSDe The current state of sUSDe.
     * @param shares The number of sUSDe shares.
     * @return The amount of underlying assets.
     */
    function sUsdePreviewRedeem(
        StakedUSDeLib.StakedUSDe calldata sUSDe,
        uint256 shares
    ) external view returns (uint256) {
        return sUSDe.previewRedeem(shares);
    }

    /**
     * @notice Returns the number of sUSDe shares that would be minted for a given asset deposit.
     * @param sUSDe The current state of sUSDe.
     * @param assets The amount of assets to deposit.
     * @return The number of sUSDe shares.
     */
    function sUsdePreviewDeposit(
        StakedUSDeLib.StakedUSDe calldata sUSDe,
        uint256 assets
    ) external view returns (uint256) {
        return sUSDe.previewDeposit(assets);
    }

    /**
     * @notice Returns the underlying assets that would be redeemed for a given amount of sFRAX shares.
     * @param sFRAX The current state of sFRAX.
     * @param shares The number of sFRAX shares.
     * @return The amount of underlying assets.
     */
    function sFraxPreviewRedeem(
        StakedFraxLib.StakedFrax calldata sFRAX,
        uint256 shares
    ) external view returns (uint256) {
        return sFRAX.previewRedeem(shares);
    }

    /**
     * @notice Returns the number of sFRAX shares that would be minted for a given asset deposit.
     * @param sFRAX The current state of sFRAX.
     * @param assets The amount of assets to deposit.
     * @return The number of sFRAX shares.
     */
    function sFraxPreviewDeposit(
        StakedFraxLib.StakedFrax calldata sFRAX,
        uint256 assets
    ) external view returns (uint256) {
        return sFRAX.previewDeposit(assets);
    }

    /**
     * @notice Returns the underlying assets that would be redeemed for a given amount of Savings DAI shares.
     * @param pot The current state of the Savings DAI pot.
     * @param shares The number of Savings DAI shares.
     * @return The amount of underlying assets.
     */
    function sDaiPreviewRedeem(SavingsDaiLib.Pot calldata pot, uint256 shares) external view returns (uint256) {
        return pot.previewRedeem(shares);
    }

    /**
     * @notice Returns the number of Savings DAI shares that would be minted for a given asset deposit.
     * @param pot The current state of the Savings DAI pot.
     * @param assets The amount of assets to deposit.
     * @return The number of Savings DAI shares.
     */
    function sDaiPreviewDeposit(SavingsDaiLib.Pot calldata pot, uint256 assets) external view returns (uint256) {
        return pot.previewDeposit(assets);
    }
}
