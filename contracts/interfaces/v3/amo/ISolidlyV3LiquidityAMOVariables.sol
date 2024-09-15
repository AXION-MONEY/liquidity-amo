// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title SolidlyV3LiquidityAMO state that can be changed
/// @notice
interface ISolidlyV3LiquidityAMOVariables {
    function treasuryVault() external view returns (address);

    function boostAmountLimit() external view returns (uint256);

    function liquidityAmountLimit() external view returns (uint256);

    function validRangeRatio() external view returns (uint256);

    function boostMultiplier() external view returns (uint256);

    function epsilon() external view returns (uint256);

    function delta() external view returns (uint256);

    function tickLower() external view returns (int24);

    function tickUpper() external view returns (int24);

    function targetSqrtPriceX96() external view returns (uint160);
}
