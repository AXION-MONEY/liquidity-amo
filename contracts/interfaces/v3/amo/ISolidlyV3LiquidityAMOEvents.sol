// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title Events emitted by SolidlyV3LiquidityAMO
/// @notice Contains all events emitted by SolidlyV3LiquidityAMO
interface ISolidlyV3LiquidityAMOEvents {
    event MintSell(uint256 boostAmountIn, uint256 usdAmountOut, uint256 dryPowderAmount);
    event AddLiquidity(uint256 boostSpent, uint256 usdSpent, uint256 liquidity);
    event UnfarmBuyBurn(
        uint256 boostRemoved,
        uint256 usdRemoved,
        uint256 liquidity,
        uint256 usdAmountIn,
        uint256 boostAmountOut,
        uint256 boostCollectedFee,
        uint256 usdCollectedFee
    );

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
