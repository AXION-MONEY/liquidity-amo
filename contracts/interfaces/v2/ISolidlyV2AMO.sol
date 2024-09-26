// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISolidlyV2AMO {
    /* ========== ROLES ========== */
    /// @notice Returns the identifier for the REWARD_COLLECTOR_ROLE
    /// @dev This role allows calling getReward()
    function REWARD_COLLECTOR_ROLE() external view returns (bytes32);

    /* ========== VARIABLES ========== */
    /// @notice Returns the address of the Solidly router
    function router() external view returns (address);

    /// @notice Returns the address of the Solidly gauge
    function gauge() external view returns (address);

    /// @notice Returns the address of the reward vault for collected rewards
    function rewardVault() external view returns (address);

    /// @notice Returns whether the given token is a whitelisted reward token
    /// @param token The address of the token to check
    /// @return true if the token is whitelisted, false otherwise
    function whitelistedRewardTokens(address token) external view returns (bool);

    /// @notice Returns the BOOST sell ratio (in 6 decimals)
    function boostSellRatio() external view returns (uint256);

    /// @notice Returns the USD buy ratio (in 6 decimals)
    function usdBuyRatio() external view returns (uint256);

    /// @notice Returns the token ID for gauge
    function tokenId() external view returns (uint256);

    /// @notice Returns a boolean indicating use or not to use the token ID
    function useTokenId() external view returns (bool);

    /* ========== FUNCTIONS ========== */
    /**
     * @notice This function sets the reward and buyback vault addresses
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param rewardVault_ The address of the reward vault
     */
    function setVault(address rewardVault_) external;

    /**
     * @notice This function sets the token id for depositing in mintSellFarm()
     * @param tokenId_ The token id
     * @param useTokenId_ A boolean indicating use or not to use the token id
     */
    function setTokenId(uint256 tokenId_, bool useTokenId_) external;

    /**
     * @notice This function sets various params for the contract
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param boostMultiplier_ The multiplier used to calculate the amount of boost to mint in addLiquidity()
     * @param validRangeRatio_ The valid range ratio for addLiquidity()
     * @param validRemovingRatio_ Set the price (<1$) on which the unfarmBuyBurn() is allowed
     * @param boostLowerPriceSell_ The new lower price bound for selling BOOST
     * @param boostUpperPriceBuy_ The new upper price bound for buying BOOST
     * @param boostSellRatio_ The new BOOST sell ratio
     * @param usdBuyRatio_ The new USD buy ratio
     */
    function setParams(
        uint256 boostMultiplier_,
        uint24 validRangeRatio_,
        uint24 validRemovingRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_,
        uint256 boostSellRatio_,
        uint256 usdBuyRatio_
    ) external;

    /**
     * @notice This function sets the reward token whitelist status
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param tokens An array of reward token addresses
     * @param isWhitelisted The new whitelist status for the tokens
     */
    function setWhitelistedTokens(address[] memory tokens, bool isWhitelisted) external;

    /**
     * @notice This function collects reward tokens from the gauge and transfers them to the reward vault
     * @dev Can only be called by an account with the REWARD_COLLECTOR_ROLE when the contract is not paused
     * @param tokens An array of reward token addresses to be collected
     * @param passTokens The boolean to determine whether tokens should be passed to getReward() function or not
     */
    function getReward(address[] memory tokens, bool passTokens) external;
}
