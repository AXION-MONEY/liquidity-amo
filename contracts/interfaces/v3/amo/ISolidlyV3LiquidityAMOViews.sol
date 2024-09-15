// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title SolidlyV3LiquidityAMO view functions
/// @notice These functions are not change the state of the contract or the chain
interface ISolidlyV3LiquidityAMOViews {
    function position() external view returns (uint128 _liquidity, uint128 boostOwed, uint128 usdOwed);

    function liquidityForUsd(uint256 usdAmount) external view returns (uint256 liquidityAmount);

    function liquidityForBoost(uint256 boostAmount) external view returns (uint256 liquidityAmount);

    function boostPrice() external view returns (uint256 price);
}
