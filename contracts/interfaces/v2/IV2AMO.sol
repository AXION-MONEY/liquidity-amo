// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IV2AMO Interface
 * @notice Interface for the V2AMO contract, defining errors, events, enums, state variable getters, and function signatures.
 */
interface IV2AMO {
    // -------------------------------------------------------------
    //                          ERRORS
    // -------------------------------------------------------------
    /// @notice Thrown when a token is not whitelisted.
    error TokenNotWhitelisted(address token);
    /// @notice Thrown when the pairToken amount output from a swap does not match the balance change.
    error SwapPairTokenAmountOutMismatch(uint256 routerOutput, uint256 balanceChange);
    /// @notice Thrown when the LP token amount output from adding liquidity does not match the balance change.
    error LpAmountOutMismatch(uint256 routerOutput, uint256 balanceChange);
    /// @notice Thrown when the reserve ratio is invalid.
    error InvalidReserveRatio(uint256 ratio);

    // -------------------------------------------------------------
    //                         EVENTS
    // -------------------------------------------------------------
    /**
     * @notice Emitted when liquidity is added and deposited into the gauge.
     * @param ionSpent ION tokens spent.
     * @param pairTokenSpent pair tokens spent.
     * @param liquidity Liquidity tokens received.
     * @param tokenId The token ID used (if applicable).
     */
    event AddLiquidityAndDeposit(uint256 ionSpent, uint256 pairTokenSpent, uint256 liquidity, uint256 indexed tokenId);

    /**
     * @notice Emitted when an unfarm-buy-burn operation is executed.
     * @param ionRemoved ION tokens removed.
     * @param pairTokenRemoved pair tokens removed.
     * @param liquidity Liquidity tokens affected.
     * @param ionAmountOut ION tokens obtained from the swap.
     */
    event UnfarmBuyBurn(uint256 ionRemoved, uint256 pairTokenRemoved, uint256 liquidity, uint256 ionAmountOut);

    /**
     * @notice Emitted when reward tokens are collected.
     * @param tokens Array of token addresses collected.
     * @param amounts Array of amounts for each token.
     */
    event GetReward(address[] tokens, uint256[] amounts);

    /**
     * @notice Emitted when the pool fee is set.
     * @param poolFee The new pool fee.
     */
    event PoolFeeSet(uint256 poolFee);

    /**
     * @notice Emitted when the reward vault address is set.
     * @param rewardVault The new reward vault address.
     */
    event VaultSet(address rewardVault);

    /**
     * @notice Emitted when the token ID is set.
     * @param tokenId The token ID.
     * @param useTokenId Boolean indicating whether to use the token ID.
     */
    event TokenIdSet(uint256 tokenId, bool useTokenId);

    /**
     * @notice Emitted when various parameters are set.
     * @param ionMultiplayer The ION multiplier.
     * @param validRangeWidth The valid range width.
     * @param validRemovingRatio The valid ratio for liquidity removal.
     * @param ionLowerPriceSell The lower price threshold for selling ION.
     * @param ionUpperPriceBuy The upper price threshold for buying ION.
     * @param ionSellRatio The ION sell ratio.
     * @param pairTokenBuyRatio The pairToken buy ratio.
     */
    event ParamsSet(
        uint256 ionMultiplayer,
        uint24 validRangeWidth,
        uint24 validRemovingRatio,
        uint256 ionLowerPriceSell,
        uint256 ionUpperPriceBuy,
        uint256 ionSellRatio,
        uint256 pairTokenBuyRatio
    );

    /**
     * @notice Emitted when reward tokens whitelist is updated.
     * @param tokens Array of token addresses.
     * @param isWhitelisted Boolean indicating the whitelist status.
     */
    event RewardTokensSet(address[] tokens, bool isWhitelisted);

    // -------------------------------------------------------------
    //                          ENUMS
    // -------------------------------------------------------------
    /**
     * @notice Enum representing the supported pool types.
     */
    enum PoolType {
        SOLIDLY_V2,
        VELO_LIKE, // Aerodrome, Velodrome
        EQUAL_LIKE // Equalizer (EQUAL on Sonic, SCALE on Base)
    }

    // -------------------------------------------------------------
    //                            ROLES
    // -------------------------------------------------------------
    /// @notice Returns the identifier for the REWARD_COLLECTOR_ROLE.
    function REWARD_COLLECTOR_ROLE() external view returns (bytes32);

    // -------------------------------------------------------------
    //                      STATE VARIABLE
    // -------------------------------------------------------------
    /**
     * @notice Returns true if the pool is stable; false otherwise.
     */
    function isStablePool() external view returns (bool);

    /**
     * @notice Returns the pool type.
     */
    function poolType() external view returns (PoolType);

    /**
     * @notice Returns the address of the Solidly factory.
     */
    function factoryAddress() external view returns (address);

    /**
     * @notice Returns the address of the router.
     */
    function routerAddress() external view returns (address);

    /**
     * @notice Returns the address of the gauge.
     */
    function gaugeAddress() external view returns (address);

    /**
     * @notice Returns the pool fee.
     */
    function poolFee() external view returns (uint256);

    /**
     * @notice Returns the reward vault address.
     */
    function rewardVault() external view returns (address);

    /**
     * @notice Checks if a token is whitelisted as a reward token.
     * @param token The token address.
     * @return True if whitelisted; false otherwise.
     */
    function whitelistedRewardTokens(address token) external view returns (bool);

    /**
     * @notice Returns the ION sell ratio.
     */
    function ionSellRatio() external view returns (uint256);

    /**
     * @notice Returns the pairToken buy ratio.
     */
    function pairTokenBuyRatio() external view returns (uint256);

    /**
     * @notice Returns the token ID for gauge deposits.
     */
    function tokenId() external view returns (uint256);

    /**
     * @notice Returns true if the token ID is used.
     */
    function useTokenId() external view returns (bool);

    // -------------------------------------------------------------
    //                          FUNCTION
    // -------------------------------------------------------------
    /**
     * @notice Sets the pool fee.
     * @param poolFee_ The new pool fee.
     */
    function setPoolFee(uint256 poolFee_) external;

    /**
     * @notice Sets the reward vault address.
     * @param rewardVault_ The new reward vault address.
     */
    function setVault(address rewardVault_) external;

    /**
     * @notice Sets the token ID and its usage flag.
     * @param tokenId_ The token ID.
     * @param useTokenId_ Boolean indicating whether to use the token ID.
     */
    function setTokenId(uint256 tokenId_, bool useTokenId_) external;

    /**
     * @notice Sets various parameters for AMO operations.
     * @param ionMultiplier_ The ION multiplier.
     * @param validRangeWidth_ The valid range width for liquidity addition.
     * @param validRemovingRatio_ The valid ratio for liquidity removal.
     * @param ionLowerPriceSell_ The lower price threshold for selling ION.
     * @param ionUpperPriceBuy_ The upper price threshold for buying ION.
     * @param ionSellRatio_ The ION sell ratio.
     * @param pairTokenBuyRatio_ The pairToken buy ratio.
     */
    function setParams(
        uint256 ionMultiplier_,
        uint24 validRangeWidth_,
        uint24 validRemovingRatio_,
        uint256 ionLowerPriceSell_,
        uint256 ionUpperPriceBuy_,
        uint256 ionSellRatio_,
        uint256 pairTokenBuyRatio_
    ) external;

    /**
     * @notice Sets the whitelist status for an array of reward tokens.
     * @param tokens An array of token addresses.
     * @param isWhitelisted Boolean indicating whether to whitelist the tokens.
     */
    function setWhitelistedTokens(address[] memory tokens, bool isWhitelisted) external;

    /**
     * @notice Collects reward tokens from the gauge and transfers them to the reward vault.
     * @param tokens An array of reward token addresses to collect.
     * @param passTokens Boolean indicating whether to pass the token array to the external getReward() function.
     */
    function getReward(address[] memory tokens, bool passTokens) external;

    /**
     * @notice Retrieves the current reserves for ION and pairToken from the pair contract.
     * @return ionReserve The reserve amount of ION (scaled as needed).
     * @return pairTokenReserve The reserve amount of pairToken (scaled as needed).
     */
    function getReserves() external view returns (uint256 ionReserve, uint256 pairTokenReserve);
}
