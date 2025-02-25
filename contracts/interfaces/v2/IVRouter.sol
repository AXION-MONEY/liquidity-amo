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

    // Errors

    /**
     * @notice Thrown when an ETH transfer fails.
     */
    error ETHTransferFailed();

    /**
     * @notice Thrown when a deadline has expired.
     */
    error Expired();

    /**
     * @notice Thrown when the input amount is insufficient.
     */
    error InsufficientAmount();

    /**
     * @notice Thrown when the amount of token A is insufficient.
     */
    error InsufficientAmountA();

    /**
     * @notice Thrown when the amount of token B is insufficient.
     */
    error InsufficientAmountB();

    /**
     * @notice Thrown when the desired amount of token A is insufficient.
     */
    error InsufficientAmountADesired();

    /**
     * @notice Thrown when the desired amount of token B is insufficient.
     */
    error InsufficientAmountBDesired();

    /**
     * @notice Thrown when the optimal amount of token A is insufficient.
     */
    error InsufficientAmountAOptimal();

    /**
     * @notice Thrown when there is insufficient liquidity in a pool.
     */
    error InsufficientLiquidity();

    /**
     * @notice Thrown when the output amount is below the minimum required.
     */
    error InsufficientOutputAmount();

    /**
     * @notice Thrown when the input amount for ETH deposit is invalid.
     */
    error InvalidAmountInForETHDeposit();

    /**
     * @notice Thrown when the token provided for ETH deposit is invalid.
     */
    error InvalidTokenInForETHDeposit();

    /**
     * @notice Thrown when the provided swap path is invalid.
     */
    error InvalidPath();

    /**
     * @notice Thrown when the first route in the swap is invalid.
     */
    error InvalidRouteA();

    /**
     * @notice Thrown when the second route in the swap is invalid.
     */
    error InvalidRouteB();

    /**
     * @notice Thrown when an operation is attempted with a token other than WETH.
     */
    error OnlyWETH();

    /**
     * @notice Thrown when the requested pool does not exist.
     */
    error PoolDoesNotExist();

    /**
     * @notice Thrown when the factory for the pool does not exist.
     */
    error PoolFactoryDoesNotExist();

    /**
     * @notice Thrown when two provided addresses are identical.
     */
    error SameAddresses();

    /**
     * @notice Thrown when a zero address is provided.
     */
    error ZeroAddress();

    // View Functions

    /**
     * @notice Returns the address of the FactoryRegistry contract.
     * @return The factory registry address.
     */
    function factoryRegistry() external view returns (address);

    /**
     * @notice Returns the default factory address used by Velodrome's PoolFactory.
     * @return The default factory address.
     */
    function defaultFactory() external view returns (address);

    /**
     * @notice Returns the address of the Voter contract.
     * @return The voter contract address.
     */
    function voter() external view returns (address);

    // The following line for WETH is commented out in the interface.
    // function weth() external view returns (IWETH);

    /**
     * @notice Structure containing parameters for zapping in and out of pools.
     * @param tokenA Address of the first token.
     * @param tokenB Address of the second token.
     * @param stable Whether the pool is stable.
     * @param factory Factory address that created the pool.
     * @param amountOutMinA Minimum amount expected from the swap leg for token A.
     * @param amountOutMinB Minimum amount expected from the swap leg for token B.
     * @param amountAMin Minimum amount of token A expected from the liquidity provision.
     * @param amountBMin Minimum amount of token B expected from the liquidity provision.
     */
    struct Zap {
        address tokenA;
        address tokenB;
        bool stable;
        address factory;
        uint256 amountOutMinA;
        uint256 amountOutMinB;
        uint256 amountAMin;
        uint256 amountBMin;
    }

    // **** VIEW/PURE FUNCTIONS ****

    /**
     * @notice Sorts two token addresses, returning the lower and higher addresses.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @return token0 The lower-valued token address.
     * @return token1 The higher-valued token address.
     */
    function sortTokens(address tokenA, address tokenB) external pure returns (address token0, address token1);

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
     * @notice Fetches and sorts the reserves for a given pool.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @param stable True if the pool is stable, false if volatile.
     * @param _factory The factory address that created the pool.
     * @return reserveA The reserve amount of the lower-valued token.
     * @return reserveB The reserve amount of the higher-valued token.
     */
    function getReserves(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory
    ) external view returns (uint256 reserveA, uint256 reserveB);

    /**
     * @notice Performs chained getAmountOut calculations on any number of pools.
     * @param amountIn The initial amount to swap.
     * @param routes An array of Route structures defining the swap path.
     * @return amounts An array of output amounts for each step in the route.
     */
    function getAmountsOut(uint256 amountIn, Route[] memory routes) external view returns (uint256[] memory amounts);

    // **** ADD LIQUIDITY ****

    /**
     * @notice Quotes the amounts required to add liquidity to a pool.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @param stable True if the pool is stable, false if volatile.
     * @param _factory The factory address for the pool.
     * @param amountADesired The desired amount of token A.
     * @param amountBDesired The desired amount of token B.
     * @return amountA The actual amount of token A to deposit.
     * @return amountB The actual amount of token B to deposit.
     * @return liquidity The liquidity tokens to be received.
     */
    function quoteAddLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external view returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /**
     * @notice Quotes the amounts received when removing liquidity from a pool.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @param stable True if the pool is stable, false if volatile.
     * @param _factory The factory address for the pool.
     * @param liquidity The amount of liquidity tokens to remove.
     * @return amountA The amount of token A received.
     * @return amountB The amount of token B received.
     */
    function quoteRemoveLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        address _factory,
        uint256 liquidity
    ) external view returns (uint256 amountA, uint256 amountB);

    /**
     * @notice Adds liquidity to a pool with two tokens.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @param stable True if the pool is stable, false if volatile.
     * @param amountADesired The desired amount of token A.
     * @param amountBDesired The desired amount of token B.
     * @param amountAMin The minimum amount of token A to deposit.
     * @param amountBMin The minimum amount of token B to deposit.
     * @param to The recipient of the liquidity tokens.
     * @param deadline The deadline by which the transaction must complete.
     * @return amountA The actual amount of token A deposited.
     * @return amountB The actual amount of token B deposited.
     * @return liquidity The liquidity tokens received.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /**
     * @notice Adds liquidity to a pool using ETH and a token.
     * @param token The token address to pair with ETH.
     * @param stable True if the pool is stable, false if volatile.
     * @param amountTokenDesired The desired amount of the token.
     * @param amountTokenMin The minimum amount of the token to deposit.
     * @param amountETHMin The minimum amount of ETH to deposit.
     * @param to The recipient of the liquidity tokens.
     * @param deadline The deadline by which the transaction must complete.
     * @return amountToken The actual amount of the token deposited.
     * @return amountETH The actual amount of ETH deposited (wrapped as WETH if necessary).
     * @return liquidity The liquidity tokens received.
     */
    function addLiquidityETH(
        address token,
        bool stable,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    // **** REMOVE LIQUIDITY ****

    /**
     * @notice Removes liquidity from a pool consisting of two tokens.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @param stable True if the pool is stable, false if volatile.
     * @param liquidity The amount of liquidity tokens to remove.
     * @param amountAMin The minimum amount of token A to receive.
     * @param amountBMin The minimum amount of token B to receive.
     * @param to The recipient of the tokens.
     * @param deadline The deadline by which the transaction must complete.
     * @return amountA The amount of token A received.
     * @return amountB The amount of token B received.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    /**
     * @notice Removes liquidity from a pool consisting of a token and ETH.
     * @param token The token address paired with ETH.
     * @param stable True if the pool is stable, false if volatile.
     * @param liquidity The amount of liquidity tokens to remove.
     * @param amountTokenMin The minimum amount of the token to receive.
     * @param amountETHMin The minimum amount of ETH to receive.
     * @param to The recipient of the tokens.
     * @param deadline The deadline by which the transaction must complete.
     * @return amountToken The amount of the token received.
     * @return amountETH The amount of ETH received.
     */
    function removeLiquidityETH(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    /**
     * @notice Removes liquidity from a pool with fee-on-transfer tokens and ETH.
     * @param token The token address paired with ETH.
     * @param stable True if the pool is stable, false if volatile.
     * @param liquidity The amount of liquidity tokens to remove.
     * @param amountTokenMin The minimum amount of the token to receive.
     * @param amountETHMin The minimum amount of ETH to receive.
     * @param to The recipient of the ETH.
     * @param deadline The deadline by which the transaction must complete.
     * @return amountETH The amount of ETH received.
     */
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    // **** SWAP FUNCTIONS ****

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
     * @notice Swaps ETH for as many output tokens as possible.
     * @param amountOutMin The minimum amount of output tokens expected.
     * @param routes An array of Route structures defining the swap path.
     * @param to The recipient of the output tokens.
     * @param deadline The deadline by which the transaction must complete.
     * @return amounts An array of token amounts for each step in the route.
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    /**
     * @notice Swaps an exact amount of tokens for as much ETH as possible.
     * @param amountIn The amount of input tokens.
     * @param amountOutMin The minimum amount of ETH expected.
     * @param routes An array of Route structures defining the swap path.
     * @param to The recipient of the ETH.
     * @param deadline The deadline by which the transaction must complete.
     * @return amounts An array of token amounts for each step in the route.
     */
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Swaps tokens without slippage protection.
     * @dev This function is considered unsafe.
     * @param amounts An array of input amounts for each swap step.
     * @param routes An array of Route structures defining the swap path.
     * @param to The recipient of the tokens.
     * @param deadline The deadline by which the transaction must complete.
     * @return amounts An array of token amounts for each step in the route.
     */
    function UNSAFE_swapExactTokensForTokens(
        uint256[] memory amounts,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);

    // **** SWAP FUNCTIONS SUPPORTING FEE-ON-TRANSFER TOKENS ****

    /**
     * @notice Swaps an exact amount of tokens for as many output tokens as possible,
     *         supporting fee-on-transfer tokens.
     * @param amountIn The amount of input tokens.
     * @param amountOutMin The minimum amount of output tokens expected.
     * @param routes An array of Route structures defining the swap path.
     * @param to The recipient of the output tokens.
     * @param deadline The deadline by which the transaction must complete.
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external;

    /**
     * @notice Swaps ETH for as many output tokens as possible,
     *         supporting fee-on-transfer tokens.
     * @param amountOutMin The minimum amount of output tokens expected.
     * @param routes An array of Route structures defining the swap path.
     * @param to The recipient of the output tokens.
     * @param deadline The deadline by which the transaction must complete.
     */
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external payable;

    /**
     * @notice Swaps an exact amount of tokens for as much ETH as possible,
     *         supporting fee-on-transfer tokens.
     * @param amountIn The amount of input tokens.
     * @param amountOutMin The minimum amount of ETH expected.
     * @param routes An array of Route structures defining the swap path.
     * @param to The recipient of the ETH.
     * @param deadline The deadline by which the transaction must complete.
     */
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external;
}
