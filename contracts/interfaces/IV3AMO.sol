// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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

    // -------------------------------------------------------------
    //                         EVENTS
    // -------------------------------------------------------------
    /**
     * @notice Emitted when liquidity is added.
     * @param ionSpent ION tokens spent.
     * @param pairTokenSpent pair tokens spent.
     * @param liquidity Liquidity tokens received.
     */
    event AddLiquidity(uint256 ionSpent, uint256 pairTokenSpent, uint256 liquidity);

    /**
     * @notice Emitted when an unfarm-buy-burn operation is executed.
     * @param ionRemoved ION tokens removed.
     * @param pairTokenRemoved pair tokens removed.
     * @param liquidity Liquidity tokens affected.
     * @param pairTokenAmountIn pair tokens used for the swap.
     * @param ionAmountOut ION tokens obtained.
     * @param ionCollectedFee ION fee collected.
     * @param pairTokenCollectedFee pairToken fee collected.
     */
    event UnfarmBuyBurn(
        uint256 ionRemoved,
        uint256 pairTokenRemoved,
        uint256 liquidity,
        uint256 pairTokenAmountIn,
        uint256 ionAmountOut,
        uint256 ionCollectedFee,
        uint256 pairTokenCollectedFee
    );

    /**
     * @notice Emitted when tick boundaries are set.
     * @param tickLower The lower tick.
     * @param tickUpper The upper tick.
     */
    event TickBoundsSet(int24 tickLower, int24 tickUpper);

    /**
     * @notice Emitted when parameters are set.
     * @param quoterAddress The quoter contract address.
     * @param validRangeWidth The valid range width.
     */
    event ParamsSet(address quoterAddress, uint24 validRangeWidth);

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
    function quoterAddress() external view returns (address);

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
     * @notice Returns details of the current liquidity position.
     * @return liquidity The amount of liquidity.
     * @return ionOwed ION tokens owed.
     * @return pairTokenOwed pair tokens owed.
     */
    function position() external view returns (uint256 liquidity, uint256 ionOwed, uint256 pairTokenOwed);

    /**
     * @notice Converts a price to sqrt price in Q64.96 format.
     * @param price The price value to be converted.
     * @return sqrtPriceX96 representation.
     */
    function toSqrtPriceX96(uint256 price) external view returns (uint160);
}
