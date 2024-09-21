// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISolidlyV2LiquidityAMO {
    /* ========== ROLES ========== */
    /// @notice Returns the identifier for the SETTER_ROLE
    /// @dev This role allows calling setParams() and setRewardTokens() to modifying certain parameters of the contract
    function SETTER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the AMO_ROLE
    /// @dev This role allows calling mintAndSellBoost(), addLiquidityAndDeposit(), mintSellFarm() and unfarmBuyBurn();
    /// actions related to the AMO (Asset Management Operations)
    function AMO_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the REWARD_COLLECTOR_ROLE
    /// @dev This role allows calling getReward(), the collection of rewards
    function REWARD_COLLECTOR_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the PAUSER_ROLE
    /// @dev This role allows calling pause(), the pausing of the contract's critical functions
    function PAUSER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the UNPAUSER_ROLE
    /// @dev This role allows calling unpause(), the unpausing of the contract's critical functions
    function UNPAUSER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the WITHDRAWER_ROLE
    /// @dev This role allows calling withdrawERC20() and withdrawERC721() for withdrawing tokens from the contract
    function WITHDRAWER_ROLE() external view returns (bytes32);

    /* ========== VARIABLES ========== */
    /// @notice Returns the address of the BOOST token
    function boost() external view returns (address);

    /// @notice Returns the address of the USD token
    function usd() external view returns (address);

    /// @notice Returns the address of the liquidity pool
    function pool() external view returns (address);

    /// @notice Returns the number of decimals used by the BOOST token
    function boostDecimals() external view returns (uint256);

    /// @notice Returns the number of decimals used by the USD token
    function usdDecimals() external view returns (uint256);

    /// @notice Returns the address of the BOOST Minter contract
    function boostMinter() external view returns (address);

    /// @notice Returns the address of the Solidly router
    function router() external view returns (address);

    /// @notice Returns the address of the Solidly gauge
    function gauge() external view returns (address);

    /// @notice Returns the address of the reward vault for collected rewards
    function rewardVault() external view returns (address);

    /// @notice Returns the address of the treasury vault for dry powder USD
    function treasuryVault() external view returns (address);

    /// @notice Returns the multiplier for BOOST (in 6 decimals)
    function boostMultiplier() external view returns (uint256);

    /// @notice Returns the valid range ratio for adding liquidity (in 6 decimals)
    function validRangeRatio() external view returns (uint24);

    /// @notice Returns the valid removing liquidity ratio (in 6 decimals)
    function validRemovingRatio() external view returns (uint24);

    /// @notice Returns the dry powder ratio to send to the treasury vault (in 6 decimals)
    function dryPowderRatio() external view returns (uint24);

    /// @notice Returns whether the given token is a whitelisted reward token
    /// @param token The address of the token to check
    /// @return true if the token is whitelisted, false otherwise
    function whitelistedRewardTokens(address token) external view returns (bool);

    /* ========== EVENTS ========== */
    event AddLiquidity(
        uint256 requestedUsdcAmount,
        uint256 requestedBoostAmount,
        uint256 usdcSpent,
        uint256 boostSpent,
        uint256 lpAmount
    );
    event RemoveLiquidity(
        uint256 requestedUsdcAmount,
        uint256 requestedBoostAmount,
        uint256 usdcGet,
        uint256 boostGet,
        uint256 lpAmount
    );

    event DepositLP(uint256 lpAmount, uint256 indexed tokenId);
    event WithdrawLP(uint256 lpAmount);

    event MintBoost(uint256 amount);
    event BurnBoost(uint256 amount);

    event Swap(address indexed from, address indexed to, uint256 amountFrom, uint256 amountTo);

    event GetReward(address[] tokens, uint256[] amounts);

    event PublicMintSellFarmExecuted(uint256 lpAmount, uint256 newBoostPrice);
    event PublicUnfarmBuyBurnExecuted(uint256 lpAmount, uint256 newBoostPrice);

    /* ========== FUNCTIONS ========== */
    /**
     * @notice Pauses the contract, disabling specific functionalities
     * @dev Only an address with the PAUSER_ROLE can call this function
     */
    function pause() external;

    /**
     * @notice Unpauses the contract, re-enabling specific functionalities
     * @dev Only an address with the UNPAUSER_ROLE can call this function
     */
    function unpause() external;

    /**
     * @notice This function sets the reward and buyback vault addresses
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param rewardVault_ The address of the reward vault
     * @param treasuryVault_ The address of the treasury vault
     */
    function setVaults(address rewardVault_, address treasuryVault_) external;

    /**
     * @notice This function sets various params for the contract
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param boostMultiplier_ The multiplier used to calculate the amount of boost to mint in addLiquidityAndDeposit()
     * @param validRangeRatio_ The valid range ratio for addLiquidityAndDeposit()
     * @param validRemovingRatio_ Set the price (<1$) on which the unfarmBuyBurn() is allowed
     * @param dryPowderRatio_ The percent of collateral that transfer to treasuryVault in mintAndSellBoost() as dry powder
     */
    function setParams(
        uint256 boostMultiplier_,
        uint24 validRangeRatio_,
        uint24 validRemovingRatio_,
        uint24 dryPowderRatio_
    ) external;

    /**
     * @notice This function sets the reward token whitelist status
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param tokens An array of reward token addresses
     * @param isWhitelisted The new whitelist status for the tokens
     */
    function setRewardTokens(address[] memory tokens, bool isWhitelisted) external;

    /**
     * @notice This function sets the token id for depositing in mintSellFarm()
     * @param tokenId_ The token id
     * @param useTokenId_ A boolean indicating use or not to use the token id
     */
    function setTokenId(uint256 tokenId_, bool useTokenId_) external;

    /**
     * @notice This function sets params for checking that related to public functions
     * @param boostLowerPriceSell_ The new lower price bound for selling BOOST
     * @param boostUpperPriceBuy_ The new upper price bound for buying BOOST
     * @param boostSellRatio_ The new BOOST sell ratio
     * @param usdBuyRatio_ The new USD buy ratio
     */
    function setPublicCheckParams(
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_,
        uint256 boostSellRatio_,
        uint256 usdBuyRatio_
    ) external;

    /**
     * @notice This function mints BOOST tokens and sells them for USD
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param boostAmount The amount of BOOST tokens to be minted and sold
     * @param minUsdAmountOut The minimum USD amount should be received following the swap
     * @param deadline Timestamp representing the deadline for the operation to be executed
     * @return usdAmountOut The USD amount that received from the swap
     * @return dryPowderAmount The USD amount that transferred to the treasury as dry powder
     */
    function mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) external returns (uint256 usdAmountOut, uint256 dryPowderAmount);

    /**
     * @notice This function adds liquidity to the BOOST-USD pool and deposits the liquidity tokens to a gauge
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param tokenId The ID of the veNFT to boost deposited liquidity
     * @param useTokenId The boolean to determine if veNFT should be employed to boost the deposited liquidity
     * @param usdAmount The amount of USD to be added as liquidity
     * @param minUsdSpend The minimum amount of USD that must be added to the pool
     * @param minLpAmount The minimum amount of LP tokens that must be minted from the operation
     * @param deadline Timestamp representing the deadline for the operation to be executed
     * @return boostSpent The BOOST amount that is spent in add liquidity
     * @return usdSpent The USD amount that is spent in add liquidity
     * @return lpAmount The LP Amount that received from add liquidity
     */
    function addLiquidityAndDeposit(
        uint256 tokenId,
        bool useTokenId,
        uint256 usdAmount,
        uint256 minUsdSpend,
        uint256 minLpAmount,
        uint256 deadline
    ) external returns (uint256 boostSpent, uint256 usdSpent, uint256 lpAmount);

    /**
     * @notice This function rebalances the BOOST-USD pool by Calling mintAndSellBoost() and addLiquidityAndDeposit()
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param boostAmount The amount of BOOST tokens to be minted and sold
     * @param minUsdAmountOut The minimum USD amount should be received following the swap
     * @param tokenId The ID of the veNFT to boost deposited liquidity
     * @param useTokenId The boolean to determine if veNFT should be employed to boost the deposited liquidity
     * @param minUsdSpend The minimum amount of USD that must be added to the pool
     * @param minLpAmount The minimum amount of LP tokens that must be minted from the operation
     * @param deadline Timestamp representing the deadline for the operation to be executed
     * @return usdAmountOut The USD amount that received from the swap
     * @return dryPowderAmount The USD amount that transferred to the treasury as dry powder
     * @return boostSpent The BOOST amount that is spent in add liquidity
     * @return usdSpent The USD amount that is spent in add liquidity
     * @return lpAmount The LP Amount that received from add liquidity
     */
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 tokenId,
        bool useTokenId,
        uint256 minUsdSpend,
        uint256 minLpAmount,
        uint256 deadline
    )
        external
        returns (uint256 usdAmountOut, uint256 dryPowderAmount, uint256 boostSpent, uint256 usdSpent, uint256 lpAmount);

    /**
     * @notice This function rebalances the BOOST-USD pool by removing liquidity, burning BOOST tokens
     * @dev Can only be called by an account with the AMO_ROLE when the contract is not paused
     * @param lpAmount The amount of liquidity tokens to be withdrawn from the gauge
     * @param minBoostRemove The minimum amount of BOOST tokens that must be removed from the pool
     * @param minUsdRemove The minimum amount of USD tokens that must be removed from the pool
     * @param deadline Timestamp representing the deadline for the operation to be executed
     * @return boostRemoved The BOOST amount that received from remove liquidity
     * @return usdRemoved The USD amount that received from remove liquidity
     * @return boostAmountOut The BOOST amount that received from the swap
     */
    function unfarmBuyBurn(
        uint256 lpAmount,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    ) external returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut);

    /**
     * @notice Mints BOOST tokens and sells them for USD, adds liquidity and farm the LP
     * @return lpAmount The LP amount that received from add liquidity
     * @return newBoostPrice The BOOST new price after mintSellFarm()
     */
    function mintSellFarm() external returns (uint256 lpAmount, uint256 newBoostPrice);

    /**
     * @notice Unfarms liquidity, buys BOOST tokens with USD, and burns them
     * @return lpAmount The LP amount that unfarmed for rebalancing the price
     * @return newBoostPrice The BOOST new price after unfarmBuyBurn()
     */
    function unfarmBuyBurn() external returns (uint256 lpAmount, uint256 newBoostPrice);

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

    /**
     * @notice This function collects reward tokens from the gauge and transfers them to the reward vault
     * @dev Can only be called by an account with the REWARD_COLLECTOR_ROLE when the contract is not paused
     * @param tokens An array of reward token addresses to be collected
     * @param passTokens The boolean to determine whether tokens should be passed to getReward() function or not
     */
    function getReward(address[] memory tokens, bool passTokens) external;

    /**
     * @notice This view function returns the total LP amount owned and staked by AMO
     * @return freeLp + stakedLp The total LP amount owned and staked by AMO
     */
    function totalLP() external view returns (uint256);

    /**
     * @notice This view function returns the current BOOST price with PRICE_DECIMALS = 6
     * @return price the current BOOST price
     */
    function boostPrice() external view returns (uint256 price);
}
