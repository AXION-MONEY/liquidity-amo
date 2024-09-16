// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title Events emitted by SolidlyV3LiquidityAMO
/// @notice Contains all events emitted by SolidlyV3LiquidityAMO
interface ISolidlyV3LiquidityAMOEvents {
    event AddLiquidity(
        uint256 requestedBoostAmount,
        uint256 requestedUsdAmount,
        uint256 boostSpent,
        uint256 usdSpent,
        uint256 liquidity
    );
    event RemoveLiquidity(
        uint256 requestedBoostAmount,
        uint256 requestedUsdAmount,
        uint256 boostGet,
        uint256 usdGet,
        uint256 liquidity
    );
    event CollectOwedTokens(uint256 boostCollected, uint256 usdCollected);

    event MintBoost(uint256 amount);
    event BurnBoost(uint256 amount);

    event Swap(address indexed from, address indexed to, uint256 amountFrom, uint256 amountTo);
}
