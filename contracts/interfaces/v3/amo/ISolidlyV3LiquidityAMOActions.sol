// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/// @title SolidlyV3LiquidityAMO actions
/// @notice Contains SolidlyV3LiquidityAMO methods that can be called by the roles
interface ISolidlyV3LiquidityAMOActions {
    function pause() external;

    function unpause() external;

    /**
     * @notice This function sets the treasury vault addresses
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param treasuryVault_ The address of the treasury vault
     */
    function setVault(address treasuryVault_) external;

    /**
     * @notice This function sets various limits for the contract
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param boostAmountLimit_ The maximum amount of BOOST for mintAndSellBoost() and unfarmBuyBurn()
     * @param liquidityAmountLimit_ The maximum amount of liquidity for unfarmBuyBurn()
     * @param validRangeRatio_ The valid range ratio for addLiquidity()
     * @param boostMultiplier_ The multiplier used to calculate the amount of boost to mint in addLiquidity()
     * @param delta_ The percent of collateral that transfer to treasuryVault in mintAndSellBoost() as dry powder
     * @param epsilon_ Set the price (<1$) on which the unfarmBuyBurn() is allowed
     */
    function setParams(
        uint256 boostAmountLimit_,
        uint256 liquidityAmountLimit_,
        uint256 validRangeRatio_,
        uint256 boostMultiplier_,
        uint256 delta_,
        uint256 epsilon_
    ) external;

    function setTickBounds(int24 tickLower_, int24 tickUpper_) external;

    function setTargetSqrtPriceX96(uint160 targetSqrtPriceX96_) external;

    /**
     * @notice This function mints BOOST tokens and sells them for USD
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param boostAmount The amount of BOOST tokens to be minted and sold
     * @param minUsdAmountOut The minimum USD amount should be received following the swap
     * @param deadline Timestamp representing the deadline for the operation to be executed
     * @return boostAmountIn The BOOST amount that sent to the pool for the swap
     * @return usdAmountOut The USD amount that received from the swap
     * @return dryPowderAmount The USD amount that transferred to the treasury as dry powder
     */
    function mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) external returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 dryPowderAmount);

    /**
     * @notice This function adds liquidity to the BOOST-USD pool
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param usdAmount The amount of USD to be added as liquidity
     * @param minBoostSpend The minimum amount of BOOST that must be added to the pool
     * @param minUsdSpend The minimum amount of USD that must be added to the pool
     * @param deadline Timestamp representing the deadline for the operation to be executed
     * @return boostSpent The BOOST amount that is spent in add liquidity
     * @return usdSpent The USD amount that is spent in add liquidity
     * @return liquidity The liquidity Amount that received from add liquidity
     */
    function addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    ) external returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity);

    /**
     * @notice This function rebalances the BOOST-USD pool by Calling mintAndSellBoost() and addLiquidity()
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param boostAmount The amount of BOOST tokens to be minted and sold
     * @param minUsdAmountOut The minimum USD amount should be received following the swap
     * @param minBoostSpend The minimum amount of BOOST that must be added to the pool
     * @param minUsdSpend The minimum amount of USD that must be added to the pool
     * @param deadline Timestamp representing the deadline for the operation to be executed
     * @return boostAmountIn The BOOST amount that sent to the pool for the swap
     * @return usdAmountOut The USD amount that received from the swap
     * @return dryPowderAmount The USD amount that transferred to the treasury as dry powder
     * @return boostSpent The BOOST amount that is spent in add liquidity
     * @return usdSpent The USD amount that is spent in add liquidity
     * @return liquidity The liquidity Amount that received from add liquidity
     */
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        external
        returns (
            uint256 boostAmountIn,
            uint256 usdAmountOut,
            uint256 dryPowderAmount,
            uint256 boostSpent,
            uint256 usdSpent,
            uint256 liquidity
        );

    /**
     * @notice This function rebalances the BOOST-USD pool by removing liquidity, buying and burning BOOST tokens
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param liquidity The amount of liquidity tokens to be removed from the pool
     * @param minBoostRemove The minimum amount of BOOST tokens that must be removed from the pool
     * @param minUsdRemove The minimum amount of USD tokens that must be removed from the pool
     * @param minBoostAmountOut The minimum BOOST amount should be received following the swap
     * @param deadline Timestamp representing the deadline for the operation to be executed
     * @return boostRemoved The BOOST amount that received from remove liquidity
     * @return usdRemoved The USD amount that received from remove liquidity
     * @return usdAmountIn The USD amount that sent to the pool for the swap
     * @return boostAmountOut The BOOST amount that received from the swap
     */
    function unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    ) external returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut);

    /**
     * @notice Withdraws ERC20 tokens from the contract
     * @dev Can only be called by an account with the WITHDRAWER_ROLE
     * @param token The address of the ERC20 token contract
     * @param amount The amount of tokens to withdraw
     * @param recipient The address to receive the tokens
     */
    function withdrawERC20(address token, uint256 amount, address recipient) external;

    /**
     * @notice Withdraws an ERC721 token from the contract
     * @dev Can only be called by an account with the WITHDRAWER_ROLE
     * @param token The address of the ERC721 token contract
     * @param tokenId The ID of the token to withdraw
     * @param recipient The address to receive the token
     */
    function withdrawERC721(address token, uint256 tokenId, address recipient) external;
}
