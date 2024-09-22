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

    event PublicMintSellFarmExecuted(uint256 liquidity, uint256 newBoostPrice);
    event PublicUnfarmBuyBurnExecuted(uint256 liquidity, uint256 newBoostPrice);

    event VaultSet(address treasuryVault);
    event TickBoundsSet(int24 tickLower, int24 tickUpper);
    event TargetSqrtPriceX96Set(uint160 targetSqrtPriceX96);
    event ParamsSet(
        uint256 boostMultiplier,
        uint24 validRangeRatio,
        uint24 validRemovingRatio,
        uint24 dryPowderRatio,
        uint24 usdUsageRatio,
        uint256 boostLowerPriceSell,
        uint256 boostUpperPriceBuy
    );
}
