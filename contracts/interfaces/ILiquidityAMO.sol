// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ILiquidityAMO {
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

    event SetVault(address treasuryVault);
    event SetParams(
        uint256 boostAmountLimit,
        uint256 liquidityAmountLimit,
        uint256 validRangeRatio,
        uint256 boostMultiplier,
        uint256 delta,
        uint256 epsilon
    );
    event SetTick(int24 tickLower, int24 tickUpper);

    function usdDecimals() external returns (uint256);

    function boostDecimals() external returns (uint256);

    function pool() external returns (address);

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
     * @return boostAmountOut The BOOST amount that received from the swap
     */
    function unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    ) external returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut);

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

    function boost() external view returns (address);

    function usd() external view returns (address);
}
