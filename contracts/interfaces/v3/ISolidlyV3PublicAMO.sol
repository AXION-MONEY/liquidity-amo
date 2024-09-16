// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title Interface for Liquidity AMO for BOOST-USD Solidly pair
/// @notice This interface defines the public functions for the PublicAMO contract
interface ISolidlyV3PublicAMO {
    ////////////////////////// EVENTS //////////////////////////
    event AMOSet(address indexed newAmoAddress);
    event LimitsSet(uint256 boostLimitToMint, uint256 liquidityToUnfarmLimit);
    event BuyAndSellBoundSet(uint256 boostUpperPriceBuy, uint256 boostLowerPriceSell);
    event MintSellFarmExecuted(uint256 boostAmountIn, uint256 usdAmountOut, uint256 liquidity);
    event UnfarmBuyBurnExecuted(uint256 liquidity, uint256 boostRemoved, uint256 usdRemoved);
    event CooldownPeriodSet(uint256 cooldownPeriod);
    event TokenSet(uint256 indexed tokenId, bool useToken);
    event BoostSellRatioSet(uint256 boostSellRatio);
    event UsdBuyRatioSet(uint256 usdBuyRatio);

    ////////////////////////// FUNCTIONS //////////////////////////

    /// @notice Initializes the PublicAMO contract
    /// @param admin_ The address of the admin
    /// @param amoAddress_ The address of the AMO contract
    function initialize(address admin_, address amoAddress_) external;

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Mints BOOST tokens and sells them for USD
    /// @return boostAmountIn The BOOST amount that sent to the pool for the swap
    /// @return usdAmountOut The USD amount that received from the swap
    /// @return dryPowderAmount The USD amount that transferred to the treasury as dry powder
    /// @return boostSpent The BOOST amount that is spent in add liquidity
    /// @return usdSpent The USD amount that is spent in add liquidity
    /// @return liquidity The liquidity Amount that received from add liquidity
    /// @return newBoostPrice The BOOST new price after mintSellFarm()
    function mintSellFarm()
        external
        returns (
            uint256 boostAmountIn,
            uint256 usdAmountOut,
            uint256 dryPowderAmount,
            uint256 boostSpent,
            uint256 usdSpent,
            uint256 liquidity,
            uint256 newBoostPrice
        );

    /// @notice Unfarms liquidity, buys BOOST tokens with USD, and burns them
    /// @param liquidityFactor A coefficient for calculated liquidityToUnfarm to adjusting the liquidity amount
    /// @return boostRemoved The amount of BOOST removed from the pool
    /// @return usdRemoved The amount of USD removed from the pool
    /// @return usdAmountIn The amount of USD spent for buying
    /// @return boostAmountOut The amount of BOOST received from buying
    /// @return newBoostPrice The BOOST new price after unfarmBuyBurn()
    function unfarmBuyBurn(
        uint24 liquidityFactor
    )
        external
        returns (
            uint256 boostRemoved,
            uint256 usdRemoved,
            uint256 usdAmountIn,
            uint256 boostAmountOut,
            uint256 newBoostPrice
        );

    /// @notice Sets the limits for minting BOOST and unfarming liquidity
    /// @param boostLimitToMint_ The new limit for minting BOOST tokens
    /// @param liquidityToUnfarmLimit_ The new limit for unfarming liquidity
    function setLimits(uint256 boostLimitToMint_, uint256 liquidityToUnfarmLimit_) external;

    /// @notice Sets the buy upper price and sell lower price bounds for BOOST tokens
    /// @param boostUpperPriceBuy_ The new upper price bound for buying BOOST
    /// @param boostLowerPriceSell_ The new lower price bound for selling BOOST
    function setBuyAndSellBound(uint256 boostUpperPriceBuy_, uint256 boostLowerPriceSell_) external;

    /// @notice Sets the address of the AMO contract
    /// @param amoAddress_ The new address of the AMO contract
    function setAmo(address amoAddress_) external;

    /// @notice Sets the cooldown period for users
    /// @param cooldownPeriod_ The new cooldown period
    function setCooldownPeriod(uint256 cooldownPeriod_) external;
}
