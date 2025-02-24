// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IMasterAMO} from "../IMasterAMO.sol";

/**
 * @title IV3AMO Interface
 * @notice Interface for the V3AMO contract defining errors, events, enums, state variables (as view functions),
 *         and function signatures.
 */
interface IV3AMO {
    // -------------------------------------------------------------
    //                          ERRORS
    // -------------------------------------------------------------
    /// @notice Thrown when an untrusted caller invokes a callback.
    error UntrustedCaller(address caller);
    /// @notice Thrown when swap delta values are invalid.
    error InvalidDelta();
    /// @notice Thrown when the owed token amounts are invalid.
    error InvalidOwed();
    /// @notice Thrown when the tokens spent are insufficient.
    error InsufficientTokenSpent();

    // -------------------------------------------------------------
    //                         EVENTS
    // -------------------------------------------------------------
    /**
     * @notice Emitted when liquidity is added.
     * @param boostSpent BOOST tokens spent.
     * @param usdSpent USD tokens spent.
     * @param liquidity Liquidity tokens received.
     */
    event AddLiquidity(uint256 boostSpent, uint256 usdSpent, uint256 liquidity);

    /**
     * @notice Emitted when an unfarm-buy-burn operation is executed.
     * @param boostRemoved BOOST tokens removed.
     * @param usdRemoved USD tokens removed.
     * @param liquidity Liquidity tokens affected.
     * @param usdAmountIn USD tokens used for the swap.
     * @param boostAmountOut BOOST tokens obtained.
     * @param boostCollectedFee BOOST fee collected.
     * @param usdCollectedFee USD fee collected.
     */
    event UnfarmBuyBurn(
        uint256 boostRemoved,
        uint256 usdRemoved,
        uint256 liquidity,
        uint256 usdAmountIn,
        uint256 boostAmountOut,
        uint256 boostCollectedFee,
        uint256 usdCollectedFee
    );

    /**
     * @notice Emitted when tick boundaries are set.
     * @param tickLower The lower tick.
     * @param tickUpper The upper tick.
     */
    event TickBoundsSet(int24 tickLower, int24 tickUpper);

    /**
     * @notice Emitted when parameters are set.
     * @param quoter The quoter contract address.
     * @param boostMultiplier The BOOST multiplier.
     * @param validRangeWidth The valid range width.
     * @param validRemovingRatio The valid ratio for liquidity removal.
     * @param boostLowerPriceSell The lower price threshold for selling BOOST.
     * @param boostUpperPriceBuy The upper price threshold for buying BOOST.
     */
    event ParamsSet(
        address quoter,
        uint256 boostMultiplier,
        uint24 validRangeWidth,
        uint24 validRemovingRatio,
        uint256 boostLowerPriceSell,
        uint256 boostUpperPriceBuy
    );

    // -------------------------------------------------------------
    //                          ENUMS
    // -------------------------------------------------------------
    /**
     * @notice Enum representing swap types.
     */
    enum SwapType {
        SELL,
        BUY
    }

    /**
     * @notice Enum representing supported pool types.
     */
    enum PoolType {
        SOLIDLY_V3,
        CL, // e.g., Aerodrome, Velodrome
        ALGEBRA_V1_0,
        ALGEBRA_V1_9,
        ALGEBRA_INTEGRAL,
        RAMSES_V2
    }

    // -------------------------------------------------------------
    //                      STATE VARIABLES
    // -------------------------------------------------------------
    /**
     * @notice Returns the pool type.
     */
    function poolType() external view returns (PoolType);

    /**
     * @notice Returns the deployer address for Algebra integral custom pools;
     *         returns the zero address for other pools.
     */
    function poolCustomDeployer() external view returns (address);

    /**
     * @notice Returns the quoter contract address.
     */
    function quoter() external view returns (address);

    /**
     * @notice Returns the lower tick of the liquidity position.
     */
    function tickLower() external view returns (int24);

    /**
     * @notice Returns the upper tick of the liquidity position.
     */
    function tickUpper() external view returns (int24);

    // -------------------------------------------------------------
    //                        FUNCTIONS
    // -------------------------------------------------------------
    /**
     * @notice Sets the tick boundaries for liquidity positions.
     * @param tickLower_ The lower tick.
     * @param tickUpper_ The upper tick.
     */
    function setTickBounds(int24 tickLower_, int24 tickUpper_) external;

    /**
     * @notice Sets various parameters for the V3AMO contract.
     * @param quoter_ The new quoter contract address.
     * @param boostMultiplier_ The BOOST multiplier.
     * @param validRangeWidth_ The valid range width.
     * @param validRemovingRatio_ The valid ratio for liquidity removal.
     * @param boostLowerPriceSell_ The lower price threshold for selling BOOST.
     * @param boostUpperPriceBuy_ The upper price threshold for buying BOOST.
     */
    function setParams(
        address quoter_,
        uint256 boostMultiplier_,
        uint24 validRangeWidth_,
        uint24 validRemovingRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_
    ) external;

    /**
     * @notice Returns details of the current liquidity position.
     * @return liquidity The amount of liquidity.
     * @return boostOwed BOOST tokens owed.
     * @return usdOwed USD tokens owed.
     */
    function position() external view returns (uint256 liquidity, uint256 boostOwed, uint256 usdOwed);

    /**
     * @notice Returns the target sqrt price for swapping operations.
     * @return The target sqrt price in Q64.96 format.
     */
    function targetSqrtPriceX96() external view returns (uint160);
}
