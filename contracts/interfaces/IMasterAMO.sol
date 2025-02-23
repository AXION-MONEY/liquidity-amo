// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IMasterAMO
 * @notice Interface defining core functions, roles, and events for Automated Market Operations (AMO).
 */
interface IMasterAMO {
    // =============================================================
    //                           ERRORS
    // =============================================================

    /// @notice Reverts when an operation is attempted with a zero address.
    error ZeroAddress();

    /// @notice Reverts when an invalid ratio value is provided.
    error InvalidRatioValue();

    /// @notice Reverts when an operation outputs insufficient tokens.
    error InsufficientOutputAmount(uint256 outputAmount, uint256 minRequired);

    /// @notice Reverts when adding liquidity is attempted with an invalid ratio.
    error InvalidRatioToAddLiquidity();

    /// @notice Reverts when removing liquidity is attempted with an invalid ratio.
    error InvalidRatioToRemoveLiquidity();

    /// @notice Reverts when the BOOST price is not within an expected range.
    error PriceNotInRange(uint256 price);

    /// @notice Reverts when an operation is attempted but the price is already within the expected range.
    error PriceAlreadyInRange(uint256 price);

    /// @notice Reverts when an unsupported paired token type is used.
    error InvalidPairedTokenType();

    // =============================================================
    //                           EVENTS
    // =============================================================

    /**
     * @notice Emitted when BOOST is minted and sold for USD.
     * @param boostAmountIn The amount of BOOST minted and sold.
     * @param usdAmountOut The amount of USD received.
     */
    event MintSell(uint256 boostAmountIn, uint256 usdAmountOut);

    /**
     * @notice Emitted when a public `mintSellFarm` operation is executed.
     * @param liquidity The amount of liquidity added.
     * @param newBoostPrice The new BOOST price after the operation.
     */
    event PublicMintSellFarmExecuted(uint256 liquidity, uint256 newBoostPrice);

    /**
     * @notice Emitted when a public `unfarmBuyBurn` operation is executed.
     * @param liquidity The amount of liquidity removed.
     * @param newBoostPrice The new BOOST price after the operation.
     */
    event PublicUnfarmBuyBurnExecuted(uint256 liquidity, uint256 newBoostPrice);

    /**
     * @notice Emitted when the target price premium is updated.
     * @param premium The new premium value.
     */
    event SetTargetPricePremium(uint256 premium);

    // =============================================================
    //                           ENUMS
    // =============================================================
    enum PairedTokenType {
        STABLE, // TODO: Consider renaming to USD for clarity
        SUSDE,
        SFRAX,
        SDAI
    }

    // =============================================================
    //                           ROLES
    // =============================================================
    /// @notice Returns the identifier for the SETTER_ROLE.
    function SETTER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the AMO_ROLE.
    function AMO_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the PAUSER_ROLE.
    function PAUSER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the UNPAUSER_ROLE.
    function UNPAUSER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the WITHDRAWER_ROLE.
    function WITHDRAWER_ROLE() external view returns (bytes32);

    // =============================================================
    //                           VARIABLES
    // =============================================================
    /// @notice Address of the BOOST token.
    function boost() external view returns (address);

    /// @notice Address of the USD token.
    function usd() external view returns (address);

    /// @notice Address of the liquidity pool.
    function pool() external view returns (address);

    /// @notice Number of decimals used by the BOOST token.
    function boostDecimals() external view returns (uint8);

    /// @notice Number of decimals used by the USD token.
    function usdDecimals() external view returns (uint8);

    /// @notice Address of the BOOST minter contract.
    function boostMinter() external view returns (address);

    /// @notice BOOST multiplier (scaled to 6 decimals).
    function boostMultiplier() external view returns (uint256);

    /// @notice Valid range ratio for adding liquidity (6 decimals).
    function validRangeWidth() external view returns (uint24);

    /// @notice Valid removing liquidity ratio (6 decimals). expected to be close to 1.
    function validRemovingRatio() external view returns (uint24);

    /// @notice BOOST lower price threshold after a sell operation (6 decimals).
    function boostLowerPriceSell() external view returns (uint256);

    /// @notice BOOST upper price threshold after a buy operation (6 decimals).
    function boostUpperPriceBuy() external view returns (uint256);

    /**
     * @notice Retrieves the current premium offset used for staked pairs in target price calculations.
     * @dev This premium value is added to the preview deposit amount from the PriceManager for staked tokens
     *      to derive the overall target price. It represents the price slippage and is expected to be lower than
     *      the pull fee.
     *
     * @return The current premium offset.
     */
    function targetPricePremium() external view returns (uint256);

    /// @notice Address of the PriceManager Contract.
    function priceManager() external view returns (address);

    /// @notice Type of the PairToken either USD or other Staked Stable types.
    function pairedTokenType() external view returns (PairedTokenType);

    // =============================================================
    //                           FUNCTIONS
    // =============================================================
    /**
     * @notice Pauses the contract.
     * @dev Only accounts with PAUSER_ROLE can invoke this.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract.
     * @dev Only accounts with UNPAUSER_ROLE can invoke this.
     */
    function unpause() external;

    /**
     * @notice Mints BOOST tokens and sells them for USD.
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param boostAmount The amount of BOOST to mint and sell.
     * @return boostAmountIn The BOOST tokens sent to the pool.
     * @return usdAmountOut The USD tokens received from the sale.
     */
    function mintAndSellBoost(uint256 boostAmount) external returns (uint256 boostAmountIn, uint256 usdAmountOut);

    /**
     * @notice Adds liquidity to the BOOST-USD pool.
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param usdAmount The USD amount to add.
     * @param minBoostSpend The minimum BOOST tokens to spend.
     * @param minUsdSpend The minimum USD tokens to spend.
     * @return boostSpent The BOOST tokens spent.
     * @return usdSpent The USD tokens spent.
     * @return liquidity The liquidity tokens received.
     */
    function addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    ) external returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity);

    /**
     * @notice Rebalances the pool by minting, selling, and adding liquidity.
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param boostAmount The BOOST amount to mint and sell.
     * @param minBoostSpend The minimum BOOST tokens to spend for liquidity.
     * @param minUsdSpend The minimum USD tokens to spend for liquidity.
     * @return boostAmountIn The BOOST tokens used in the swap.
     * @return usdAmountOut The USD tokens received from the swap.
     * @return boostSpent The BOOST tokens spent in liquidity addition.
     * @return usdSpent The USD tokens spent in liquidity addition.
     * @return liquidity The liquidity tokens received.
     */
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    )
        external
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 boostSpent, uint256 usdSpent, uint256 liquidity);

    /**
     * @notice Rebalances the pool by removing liquidity, buying, and burning BOOST tokens.
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param liquidity The liquidity tokens to remove.
     * @param minBoostRemove The minimum BOOST tokens to remove.
     * @param minUsdRemove The minimum USD tokens to remove.
     * @return boostRemoved The BOOST tokens removed.
     * @return usdRemoved The USD tokens removed.
     * @return usdAmountIn The USD tokens used to buy BOOST.
     * @return boostAmountOut The BOOST tokens obtained after the purchase.
     */
    function unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove
    ) external returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut);

    /**
     * @notice Mints, sells, and farms BOOST tokens when BOOST is over peg.
     * @return liquidity The liquidity tokens received.
     * @return newBoostPrice The new average BOOST price after the operation.
     */
    function mintSellFarm() external returns (uint256 liquidity, uint256 newBoostPrice);

    /**
     * @notice Unfarms liquidity, buys, and burns BOOST tokens when BOOST is under peg.
     * @return liquidity The liquidity tokens affected.
     * @return newBoostPrice The new average BOOST price after the operation.
     */
    function unfarmBuyBurn() external returns (uint256 liquidity, uint256 newBoostPrice);

    /**
     * @notice Withdraws ERC20 tokens from the contract.
     * @param token The ERC20 token address.
     * @param amount The amount to withdraw.
     * @param recipient The address to receive the tokens.
     */
    function withdrawERC20(address token, uint256 amount, address recipient) external;

    /**
     * @notice Retrieves the current BOOST price.
     * @return price The current BOOST price (using 6 decimals).
     */
    function boostPrice() external view returns (uint256 price);


    /**
     * @notice Retrieves the target price for Boost based on the paired token type.
     * @dev The target price is determined as follows:
     *      - For a STABLE paired token, the target price is set to a fixed base unit (1 × 10^PRICE_DECIMALS).
     *      - For staked pairs (SUSDE, SFRAX, SDAI), the target price is calculated by querying the corresponding
     *        preview deposit function from the PriceManager using the base unit, and then adding a price offset
     *        (targetPricePremium). This premium represents a slippage adjustment and must be set lower than the pull fee.
     *
     * @return price The computed target price.
     */
    function targetPrice() external view returns (uint256 price);
}
