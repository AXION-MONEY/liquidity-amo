// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import "./IAlgebraPool.sol";

/// @title The interface for an Algebra Integral Pool
interface IAlgebraIntegralPool is IAlgebraPool {
    /**
     * @notice Burn liquidity from the sender and account tokens owed for the liquidity to the position
     * @dev Can be used to trigger a recalculation of fees owed to a position by calling with an amount of 0
     * @dev Fees must be collected separately via a call to #collect
     * @param bottomTick The lower tick of the position for which to burn liquidity
     * @param topTick The upper tick of the position for which to burn liquidity
     * @param amount How much liquidity to burn
     * @param data Any data that should be passed through to the plugin
     * @return amount0 The amount of token0 sent to the recipient
     * @return amount1 The amount of token1 sent to the recipient
     */
    function burn(
        int24 bottomTick,
        int24 topTick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    /// @dev updates default community fee for new pools
    /// @param newDefaultCommunityFee The new community fee, _must_ be <= MAX_COMMUNITY_FEE
    function setDefaultCommunityFee(uint16 newDefaultCommunityFee) external;

    /// @dev updates vaultFactory address
    /// @param newVaultFactory address of new vault factory
    function setVaultFactory(address newVaultFactory) external;
}
