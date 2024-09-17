// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @title Interface for Liquidity AMO for BOOST-USD Solidly pair
/// @notice This interface defines the public functions for the PublicAMO contract
interface ISolidlyV2PublicAMO {
    ////////////////////////// EVENTS //////////////////////////
    event AMOSet(address indexed newAmoAddress);
    event LimitsSet(uint256 boostLimitToMint, uint256 lpLimitToUnfarm);
    event BuyAndSellBoundSet(uint256 boostUpperPriceBuy, uint256 boostLowerPriceSell);
    event MintSellFarmExecuted(uint256 boostAmountIn, uint256 usdAmountOut, uint256 lpAmount, uint256 newBoostPrice);
    event UnfarmBuyBurnExecuted(
        uint256 lpAmount,
        uint256 boostRemoved,
        uint256 usdRemoved,
        uint256 boostAmountOut,
        uint256 newBoostPrice
    );
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
    /// @return boostAmountIn The amount of BOOST is used in selling BOOST
    /// @return usdAmountOut The amount of USD received from selling BOOST
    /// @return lpAmount The LP Amount that received from add liquidity
    /// @return newBoostPrice  The BOOST new price after mintSellFarm()
    function mintSellFarm()
        external
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 lpAmount, uint256 newBoostPrice);

    /// @notice Unfarms liquidity, buys BOOST tokens with USD, and burns them
    /// @return boostRemoved The amount of BOOST removed from the pool
    /// @return usdRemoved The amount of USD removed from the pool
    /// @return boostAmountOut The amount of BOOST received from buying
    /// @return newBoostPrice  The BOOST new price after unfarmBuyBurn()
    function unfarmBuyBurn()
        external
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut, uint256 newBoostPrice);

    /// @notice Sets the limits for minting BOOST and unfarming LP tokens
    /// @param boostLimitToMint_ The new limit for minting BOOST tokens
    /// @param lpLimitToUnfarm_ The new limit for unfarming LP tokens
    function setLimits(uint256 boostLimitToMint_, uint256 lpLimitToUnfarm_) external;

    /// @notice Sets the buy upper price and sell lower price bounds for BOOST tokens
    /// @param boostUpperPriceBuy_ The new upper price bound for buying BOOST
    /// @param boostLowerPriceSell_ The new lower price bound for selling BOOST
    function setBuyAndSellBound(uint256 boostUpperPriceBuy_, uint256 boostLowerPriceSell_) external;

    /// @notice Sets the address of the AMO contract
    /// @param amoAddress_ The new address of the AMO contract
    function setAmo(address amoAddress_) external;

    /// @notice Sets the token id for depositing in mintSellFarm
    /// @param tokenId_ The token id
    /// @param useToken_ A boolean indicating use or not to use the token id
    function setToken(uint256 tokenId_, bool useToken_) external;

    /// @notice Sets the BOOST sell ratio for mintSell
    /// @param boostSellRatio_ The new BOOST sell ratio
    function setBoostSellRatio(uint256 boostSellRatio_) external;

    /// @notice Sets the USD buy ratio
    /// @param usdBuyRatio_ The new USD buy ratio
    function setUsdBuyRatio(uint256 usdBuyRatio_) external;
}
