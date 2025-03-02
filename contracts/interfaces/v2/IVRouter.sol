// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/**
 * @title IVRouter Interface
 * @notice This interface defines the functions, errors, and structures for the Velodrome Router.
 */
interface IVRouter {
    /**
     * @notice Represents a trading route used in token swaps.
     * @param from The token address to swap from.
     * @param to The token address to swap to.
     * @param stable Whether the pool is stable.
     * @param factory The factory address associated with the pool.
     */
    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    /**
     * @notice Returns the default factory address used by Velodrome's PoolFactory.
     * @return The default factory address.
     */
    function defaultFactory() external view returns (address);

    /**
     * @notice Calculates the pool address for two tokens given a factory.
     * @dev Reverts if the factory is not approved by the FactoryRegistry.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @param stable True if the pool is stable, false if volatile.
     * @param _factory The factory address that created the pool.
     * @return pool The computed pool address.
     */
    function poolFor(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory
    ) external view returns (address pool);

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * @param amountIn The amount of input tokens.
     * @param amountOutMin The minimum amount of output tokens expected.
     * @param routes An array of Route structures defining the swap path.
     * @param to The recipient of the output tokens.
     * @param deadline The deadline by which the transaction must complete.
     * @return amounts An array of token amounts for each step in the route.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Quote the amount deposited into a Pool
     * @param tokenA .
     * @param tokenB .
     * @param stable True if pool is stable, false if volatile
     * @param _factory Address of PoolFactory for tokenA and tokenB
     * @param amountADesired Amount of tokenA desired to deposit
     * @param amountBDesired Amount of tokenB desired to deposit
     * @return amountA Amount of tokenA to actually deposit
     * @return amountB Amount of tokenB to actually deposit
     * @return liquidity Amount of liquidity token returned from deposit
     */
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external view returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}
