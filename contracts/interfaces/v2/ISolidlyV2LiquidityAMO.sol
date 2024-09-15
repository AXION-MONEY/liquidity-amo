// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISolidlyV2LiquidityAMO {
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

    event SetRewardToken(address[] token, bool isWhitelisted);
    event SetVaults(address rewardVault, address treasuryVault);
    event SetParams(
        uint256 boostAmountLimit,
        uint256 lpAmountLimit,
        uint256 validRangeRatio,
        uint256 boostMultiplier,
        uint256 delta,
        uint256 epsilon
    );

    function usdDecimals() external returns (uint256);

    function boostDecimals() external returns (uint256);

    function usd_boost() external returns (address);

    /**
     * @notice This function sets the reward and buyback vault addresses
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param rewardVault_ The address of the reward vault
     */
    function setVaults(address rewardVault_, address treasuryVault_) external;

    /**
     * @notice This function sets various limits for the contract
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param boostAmountLimit_ The maximum amount of BOOST for mintAndSellBoost() and unfarmBuyBurn()
     * @param lpAmountLimit_ The maximum amount of LP tokens for unfarmBuyBurn()
     * @param validRangeRatio_ The valid range ratio for addLiquidityAndDeposit()
     * @param boostMultiplier_ The multiplier used to calculate the amount of boost to mint in addLiquidityAndDeposit()
     * @param delta_ The percent of collateral that transfer to treasuryVault in mintAndSellBoost() as dry powder
     * @param epsilon_ Set the price (<1$) on which the unfarmBuyBurn() is allowed
     */
    function setParams(
        uint256 boostAmountLimit_,
        uint256 lpAmountLimit_,
        uint256 validRangeRatio_,
        uint256 boostMultiplier_,
        uint256 delta_,
        uint256 epsilon_
    ) external;

    /**
     * @notice This function sets the reward token whitelist status
     * @dev Can only be called by an account with the SETTER_ROLE
     * @param tokens An array of reward token addresses
     * @param isWhitelisted The new whitelist status for the tokens
     */
    function setRewardToken(address[] memory tokens, bool isWhitelisted) external;

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
     * @notice This function collects reward tokens from the gauge and transfers them to the reward vault
     * @dev Can only be called by an account with the REWARD_COLLECTOR_ROLE when the contract is not paused
     * @param tokens An array of reward token addresses to be collected
     * @param passTokens The boolean to determine whether tokens should be passed to getReward() function or not
     */
    function getReward(address[] memory tokens, bool passTokens) external;

    /**
     * @notice This function allows to call arbitrary functions on external contracts
     * @dev Can only be called by an account with the OPERATOR_ROLE
     * @param _target The address of the external contract to call
     * @param _calldata The calldata to be passed to the external contract call
     * @return _success A boolean indicating whether the call was successful
     * @return _resultdata The data returned by the external contract call
     */
    function _call(
        address _target,
        bytes calldata _calldata
    ) external payable returns (bool _success, bytes memory _resultdata);

    /**
     * @notice This view function return the total LP amount owned and staked by AMO
     * @return freeLp + stakedLp The total LP amount owned and staked by AMO
     */
    function totalLP() external view returns (uint256);

    function boost() external view returns (address);

    function usd() external view returns (address);
}
