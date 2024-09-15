// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title SolidlyV3LiquidityAMO state that never changes
/// @notice These parameters are fixed for contract forever, i.e., the methods will always return the same values
interface ISolidlyV3LiquidityAMOImmutables {
    function boost() external view returns (address);

    function usd() external view returns (address);

    function pool() external view returns (address);

    function boostDecimals() external view returns (uint8);

    function usdDecimals() external view returns (uint8);

    function boostMinter() external view returns (address);
}
