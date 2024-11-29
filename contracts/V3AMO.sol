// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "./MasterAMO.sol";
import "./interfaces/v3/IUniswapV3Pool.sol";
import "./interfaces/v3/quoter/IQuoterV2.sol";
import {ISolidlyV3Pool} from "./interfaces/v3/ISolidlyV3Pool.sol";
import {IV3AMO} from "./interfaces/v3/IV3AMO.sol";

contract V3AMO is IV3AMO, MasterAMO {
    /* ========== ERRORS ========== */
    error ExcessiveLiquidityRemoval(uint256 liquidity, uint256 unusedUsdAmount);
    error UntrustedCaller(address caller);
    error InvalidDelta();
    error InvalidOwed();
    error InsufficientTokenSpent();


    /* ========== EVENTS ========== */
    event AddLiquidity(uint256 boostSpent, uint256 usdSpent, uint256 liquidity);
    event UnfarmBuyBurn(
        uint256 boostRemoved,
        uint256 usdRemoved,
        uint256 liquidity,
        uint256 usdAmountIn,
        uint256 boostAmountOut,
        uint256 boostCollectedFee,
        uint256 usdCollectedFee
    );

    event TickBoundsSet(int24 tickLower, int24 tickUpper);
    event TargetSqrtPriceX96Set(uint160 targetSqrtPriceX96);
    event ParamsSet(
        address quoter,
        uint256 boostMultiplier,
        uint24 validRangeWidth,
        uint24 validRemovingRatio,
        uint24 usdUsageRatio,
        uint256 boostLowerPriceSell,
        uint256 boostUpperPriceBuy
    );
    /* ========== VARIABLES ========== */
    /// @inheritdoc IV3AMO
    uint24 public override usdUsageRatio;
    /// @inheritdoc IV3AMO
    int24 public override tickLower;
    /// @inheritdoc IV3AMO
    int24 public override tickUpper;
    /// @inheritdoc IV3AMO
    uint160 public override targetSqrtPriceX96;
    /// @inheritdoc IV3AMO
    address public override quoter;

    /* ========== CONSTANTS ========== */
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint256 internal constant Q96 = 2 ** 96;
    uint256 internal constant LIQUIDITY_COEFF = 995000;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address pool_,
        address quoter_,
        address boostMinter_,
        int24 tickLower_,
        int24 tickUpper_,
        uint160 targetSqrtPriceX96_,
        uint256 boostMultiplier_,
        uint24 validRangeWidth_,
        uint24 validRemovingRatio_,
        uint24 usdUsageRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_
    ) public initializer {
        super.initialize(admin, boost_, usd_, pool_, boostMinter_);

        _grantRole(SETTER_ROLE, msg.sender);
        setTickBounds(tickLower_, tickUpper_);
        setTargetSqrtPriceX96(targetSqrtPriceX96_);
        setParams(
            quoter_,
            boostMultiplier_,
            validRangeWidth_,
            validRemovingRatio_,
            usdUsageRatio_,
            boostLowerPriceSell_,
            boostUpperPriceBuy_
        );
        _revokeRole(SETTER_ROLE, msg.sender);
    }

    ////////////////////////// SETTER_ROLE ACTIONS //////////////////////////
    /// @inheritdoc IV3AMO
    function setTickBounds(int24 tickLower_, int24 tickUpper_) public override onlyRole(SETTER_ROLE) {
        tickLower = tickLower_;
        tickUpper = tickUpper_;
        emit TickBoundsSet(tickLower, tickUpper);
    }

    /// @inheritdoc IV3AMO
    function setTargetSqrtPriceX96(uint160 targetSqrtPriceX96_) public override onlyRole(SETTER_ROLE) {
        if (targetSqrtPriceX96_ <= MIN_SQRT_RATIO || targetSqrtPriceX96_ >= MAX_SQRT_RATIO) revert InvalidRatioValue();
        targetSqrtPriceX96 = targetSqrtPriceX96_;
        emit TargetSqrtPriceX96Set(targetSqrtPriceX96);
    }

    /// @inheritdoc IV3AMO
    /// @inheritdoc IV3AMO
    function setParams(
        address quoter_,
        uint256 boostMultiplier_,
        uint24 validRangeWidth_,
        uint24 validRemovingRatio_,
        uint24 usdUsageRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_
    ) public override onlyRole(SETTER_ROLE) {
        if (validRangeWidth_ > FACTOR || validRemovingRatio_ < FACTOR || usdUsageRatio_ > FACTOR)
            revert InvalidRatioValue();
        // validRangeWidth is a few percentage points (scaled with FACTOR). So it needs to be lower than 1 (scaled with FACTOR)
        // validRemovingRatio needs to be greater than 1 (we remove more BOOST than USD otherwise the pool is balanced)
        quoter = quoter_;
        boostMultiplier = boostMultiplier_;
        validRangeWidth = validRangeWidth_;
        validRemovingRatio = validRemovingRatio_;
        usdUsageRatio = usdUsageRatio_;
        boostLowerPriceSell = boostLowerPriceSell_;
        boostUpperPriceBuy = boostUpperPriceBuy_;
        emit ParamsSet(
            quoter,
            boostMultiplier,
            validRangeWidth,
            validRemovingRatio,
            usdUsageRatio,
            boostLowerPriceSell,
            boostUpperPriceBuy
        );
    }

    /**
     * @dev Internal function to handle swap callbacks from Uniswap V3 pools.
     * @param amount0Delta Amount of token0 involved in the swap.
     * @param amount1Delta Amount of token1 involved in the swap.
     * @param data Encoded swap type data.
     * @description the pool uses _swapCallback to buy (resp to sell) the desired amount of BOOST to repeg in UnfarmBuyBurn (resp. in MintSellFarm)
     * @motivation: calling _swapCallback is more gas efficient than calling the router —- in effect we're using it as an efficient and secure call to the router
     */
    function _swapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) internal {
        if (msg.sender != pool) revert UntrustedCaller(msg.sender);

        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0Delta, amount1Delta);
        SwapType swapType = abi.decode(data, (SwapType));
        if (swapType == SwapType.SELL) {
            uint256 boostAmountIn = uint256(boostDelta);
            uint256 usdAmountOut = uint256(-usdDelta);
            if (balanceOfToken(usd) < usdAmountOut || boostAmountIn > toBoostAmount(usdAmountOut))
                revert InvalidDelta();
            IMinter(boostMinter).protocolMint(pool, boostAmountIn);
        } else if (swapType == SwapType.BUY) {
            uint256 usdAmountIn = uint256(usdDelta);
            uint256 boostAmountOut = uint256(-boostDelta);
            if (balanceOfToken(boost) < boostAmountOut || usdAmountIn > toUsdAmount(boostAmountOut))
                revert InvalidDelta();
            IERC20Upgradeable(usd).safeTransfer(pool, usdAmountIn);
        }
    }
    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    function _mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) internal override returns (uint256 boostAmountIn, uint256 usdAmountOut) {
        // Mint the specified amount of BOOST tokens to this contract's address
        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of the minted BOOST tokens to the pool
        IERC20Upgradeable(boost).approve(pool, boostAmount);

        // Execute the swap
        // If boost < usd, we are selling BOOST for USD, otherwise vice versa
        // The swap is executed at the targetSqrtPriceX96, and must meet the minimum USD amount
        (int256 amount0, int256 amount1) = ISolidlyV3Pool(pool).swap(
            address(this),
            boost < usd,
            int256(boostAmount), // Amount of BOOST tokens being swapped
            targetSqrtPriceX96, // The target square root price
            minUsdAmountOut, // Minimum acceptable amount of USD to receive from the swap
            deadline
        );

        // Revoke approval from the pool
        IERC20Upgradeable(boost).approve(pool, 0);

        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0, amount1);
        boostAmountIn = uint256(boostDelta); // BOOST tokens used in the swap
        usdAmountOut = uint256(-usdDelta); // USD tokens received from the swap
        if (toBoostAmount(usdAmountOut) <= boostAmountIn)
            revert InsufficientOutputAmount({outputAmount: toBoostAmount(usdAmountOut), minRequired: boostAmountIn});

        // Burn any excess BOOST that wasn't used in the swap
        if (boostAmount > boostAmountIn) IBoostStablecoin(boost).burn(boostAmount - boostAmountIn);

        emit MintSell(boostAmountIn, usdAmountOut);
    }

    /**
    * @notice Calculates the liquidity required to match a given USD amount.
     * @dev This function ensures accurate liquidity estimation by using the current pool state and tick bounds.
     *      It avoids inaccuracies by leveraging the Uniswap V3 price and liquidity formulas.
     * @param usdAmount The amount of USD for which the corresponding liquidity is to be calculated.
     * @return liquidity The calculated liquidity amount corresponding to the given USD amount.
     */
    function _getLiquidityForUsdAmount(uint256 usdAmount) internal view returns (uint256 liquidity) {
        // Step 1: Fetch the current price and pool data
        uint160 sqrtRatioX96;
        (sqrtRatioX96, , , ) = ISolidlyV3Pool(pool).slot0();

        // Step 2: Fetch the price bounds corresponding to the tickLower and tickUpper
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        // Step 3: Sort amounts to determine the maximum amounts of token0 (BOOST) and token1 (USD)
        (uint256 amount0, uint256 amount1) = sortAmounts(type(uint128).max, usdAmount);

        // Step 4: Use the Uniswap V3 LiquidityAmounts library to calculate liquidity
        liquidity = uint256(
            LiquidityAmounts.getLiquidityForAmounts(
                sqrtRatioX96, // Current pool price
                sqrtRatioAX96, // Lower bound price
                sqrtRatioBX96, // Upper bound price
                amount0, // Maximum BOOST
                amount1 // Maximum USD
            )
        );
    }


    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    ) internal override returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity) {
        // Calculate the amount of BOOST to mint based on the usdAmount and boostMultiplier
        uint256 boostAmount = (toBoostAmount(usdAmount) * boostMultiplier) / FACTOR;

        // Mint the specified amount of BOOST tokens to this contract's address
        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of BOOST and USD tokens to the pool
        IERC20Upgradeable(boost).approve(pool, boostAmount);
        IERC20Upgradeable(usd).approve(pool, usdAmount);

        (uint256 amount0Min, uint256 amount1Min) = sortAmounts(minBoostSpend, minUsdSpend);

        uint128 currentLiquidity = ISolidlyV3Pool(pool).liquidity();
        liquidity = (usdAmount * currentLiquidity) / IERC20Upgradeable(usd).balanceOf(pool);

        // Add liquidity to the BOOST-USD pool within the specified tick range
        (uint256 amount0, uint256 amount1) = ISolidlyV3Pool(pool).mint(
            address(this),
            tickLower,
            tickUpper,
            uint128(liquidity),
            amount0Min,
            amount1Min,
            deadline
        );

        // Revoke approval from the pool
        IERC20Upgradeable(boost).approve(pool, 0);
        IERC20Upgradeable(usd).approve(pool, 0);

        (boostSpent, usdSpent) = sortAmounts(amount0, amount1);

        // Calculate valid range for USD spent based on BOOST spent and validRangeWidth
        uint256 validRange = (boostSpent * validRangeWidth) / FACTOR;
        if (toBoostAmount(usdSpent) <= boostSpent - validRange || toBoostAmount(usdSpent) >= boostSpent + validRange)
            revert InvalidRatioToAddLiquidity();

        // Burn any excess BOOST not used in liquidity
        if (boostAmount > boostSpent) IBoostStablecoin(boost).burn(boostAmount - boostSpent);

        emit AddLiquidity(boostSpent, usdSpent, liquidity);
    }


    /**
     * @notice Removes liquidity, swaps USD for BOOST to stabilize the price, and burns excess BOOST.
     * @dev Fixes the issue of incorrectly estimating liquidity in V3 pools by using `quoteSwap`
     *      to calculate the required amount of liquidity based on the deviation from the target price.
     *      This ensures the liquidity removed and USD swapped are calculated precisely.
     * @param liquidity Amount of liquidity to remove from the pool.
     * @param minBoostRemove Minimum amount of BOOST tokens to remove when withdrawing liquidity.
     * @param minUsdRemove Minimum amount of USD tokens to remove when withdrawing liquidity.
     * @return boostRemoved Amount of BOOST tokens removed from the pool.
     * @return usdRemoved Amount of USD tokens removed from the pool.
     * @return usdAmountIn Amount of USD tokens swapped into BOOST.
     * @return boostAmountOut Amount of BOOST tokens bought and burned.
     */
    function _unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove
    )
    internal
    override
    returns (
        uint256 boostRemoved,
        uint256 usdRemoved,
        uint256 usdAmountIn,
        uint256 boostAmountOut
    )
    {
        // Step 1: Remove liquidity from the pool
        (uint256 amount0Min, uint256 amount1Min) = sortAmounts(minBoostRemove, minUsdRemove);
        (
            uint256 amount0FromBurn,
            uint256 amount1FromBurn,
            uint128 amount0Collected,
            uint128 amount1Collected
        ) = ISolidlyV3Pool(pool).burnAndCollect(
            address(this),
            tickLower,
            tickUpper,
            uint128(liquidity),
            amount0Min,
            amount1Min,
            type(uint128).max,
            type(uint128).max,
            block.timestamp + 90
        );

        // Step 2: Sort amounts to determine BOOST and USD values
        (boostRemoved, usdRemoved) = sortAmounts(amount0FromBurn, amount1FromBurn);
        (uint256 boostCollected, uint256 usdCollected) = sortAmounts(amount0Collected, amount1Collected);

        // Step 3: Validate that the removed liquidity adheres to the required ratio
        if ((boostRemoved * validRemovingRatio) / FACTOR < toBoostAmount(usdRemoved)) {
            revert InvalidRatioToRemoveLiquidity();
        }

        // Step 4: Use quoteSwap to determine the USD needed to bring the price back to peg
        (int256 amount0, int256 amount1, , , ) = ISolidlyV3Pool(pool).quoteSwap(
            boost > usd, // zeroForOne
            int256(usdRemoved), // Maximum USD to use for the swap
            targetSqrtPriceX96 // Target price for the swap
        );

        // Step 5: Execute the swap
        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0, amount1);
        usdAmountIn = uint256(usdDelta); // USD spent in the swap
        boostAmountOut = uint256(-boostDelta); // BOOST tokens received from the swap

        // Step 6: Calculate unused USD amount and add it back as liquidity
        uint256 unusedUsdAmount = usdRemoved - usdAmountIn;
        if (unusedUsdAmount > 0) _addLiquidity(unusedUsdAmount, 1, 1);

        // Step 7: Burn BOOST tokens collected and obtained from the swap
        IBoostStablecoin(boost).burn(boostCollected + boostAmountOut);

        // Emit event for the UnfarmBuyBurn operation
        emit UnfarmBuyBurn(
            boostRemoved,
            usdRemoved,
            liquidity,
            usdAmountIn,
            boostAmountOut,
            boostCollected - boostRemoved, // boostCollectedFee
            usdCollected - usdRemoved // usdCollectedFee
        );
    }

    ////////////////////////// PUBLIC FUNCTIONS //////////////////////////
    function _mintSellFarm() internal override returns (uint256 liquidity, uint256 newBoostPrice) {
        uint256 maxBoostAmount = IERC20Upgradeable(boost).balanceOf(pool);
        bool zeroForOne = boost < usd; // Determine the direction of the swap
        // Quote the swap to calculate how much BOOST can be swapped for USD
        (int256 amount0, int256 amount1, , , ) = ISolidlyV3Pool(pool).quoteSwap(
            zeroForOne,
            int256(maxBoostAmount),
            targetSqrtPriceX96
        );
        // Determine the amount of BOOST based on the direction of the swap
        uint256 boostAmount;
        if (zeroForOne) boostAmount = uint256(amount0);
        else boostAmount = uint256(amount1);

        (, , , , liquidity) = _mintSellFarm(
            boostAmount,
            1, // minUsdAmountOut
            1, // minBoostSpend
            1, // minUsdSpend
            block.timestamp + 1 // deadline
        );

        newBoostPrice = boostPrice();
    }

    /**
    * @notice Removes liquidity, stabilizes BOOST price, and calculates the new price post-operation.
     * @dev Fixes the issue of relying on incorrect liquidity calculations by using `quoteSwap`
     *      to estimate the required USD amount and `_getLiquidityForUsdAmount` to determine the corresponding liquidity.
     *      Ensures the operation only removes the necessary liquidity to achieve the target price, preventing overshooting.
     * @return liquidity Amount of liquidity removed from the pool.
     * @return newBoostPrice The updated BOOST price after the operation.
     */
    function _unfarmBuyBurn() internal override returns (uint256 liquidity, uint256 newBoostPrice) {
        // Step 1: Fetch the current position's total liquidity
        (uint256 positionLiquidity, , ) = position();

        // Step 2: Use `quoteSwap` to calculate the USD amount needed to bring BOOST to the target price
        uint256 amountIn;
        (int256 amount0, int256 amount1, , , ) = ISolidlyV3Pool(pool).quoteSwap(
            boost > usd, // Determine swap direction: USD to BOOST
            type(int256).max, // Maximum amount of USD to swap
            targetSqrtPriceX96 // Target price for BOOST
        );

        // Extract the USD amount required for the swap
        (, int256 usdDelta) = sortAmounts(amount0, amount1);
        amountIn = uint256(usdDelta); // USD required for the swap

        // Step 3: Determine the liquidity corresponding to the calculated USD amount
        liquidity = _getLiquidityForUsdAmount(amountIn);

        // Step 4: Ensure the liquidity to be removed does not exceed the current position's liquidity
        if (liquidity > positionLiquidity) liquidity = positionLiquidity;

        // Step 5: Call the internal `_unfarmBuyBurn` function to execute the operation
        _unfarmBuyBurn(
            liquidity,
            1, // Minimum BOOST to remove
            1  // Minimum USD to remove
        );

        // Step 6: Calculate the new BOOST price after the operation
        newBoostPrice = boostPrice();
    }


    function _validateSwap(bool boostForUsd) internal view override {}

    ////////////////////////// VIEW FUNCTIONS //////////////////////////
    /// @inheritdoc IMasterAMO
    function boostPrice() public view override returns (uint256 price) {
        (uint160 _sqrtPriceX96, , , ) = ISolidlyV3Pool(pool).slot0();
        uint256 sqrtPriceX96 = uint256(_sqrtPriceX96);
        if (boost < usd) {
            price = (10 ** (boostDecimals - usdDecimals + PRICE_DECIMALS) * sqrtPriceX96 ** 2) / Q96 ** 2;
        } else {
            if (sqrtPriceX96 >= Q96) {
                price = 10 ** (boostDecimals - usdDecimals + PRICE_DECIMALS) / (sqrtPriceX96 ** 2 / Q96 ** 2);
            } else {
                price = (10 ** (boostDecimals - usdDecimals + PRICE_DECIMALS) * Q96 ** 2) / sqrtPriceX96 ** 2;
            }
        }
    }

    function position() public view override returns (uint256 liquidity, uint256 boostOwed, uint256 usdOwed) {
        bytes32 key = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        uint128 _liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        (_liquidity, tokensOwed0, tokensOwed1) = ISolidlyV3Pool(pool).positions(key);
        if (_liquidity > 0) liquidity = uint256(_liquidity);
        (boostOwed, usdOwed) = sortAmounts(uint256(tokensOwed0), uint256(tokensOwed1));
    }

}
