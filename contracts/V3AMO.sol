// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "./MasterAMO.sol";
import "./interfaces/v3/IUniswapV3Pool.sol";
import {ISolidlyV3Pool} from "./interfaces/v3/ISolidlyV3Pool.sol";
import {ISolidlyV3Factory} from "./interfaces/v3/ISolidlyV3Factory.sol";
import {IRewardsDistributor} from "./interfaces/v3/IRewardsDistributor.sol";
import {IV3AMO} from "./interfaces/v3/IV3AMO.sol";
import {IUniswapV3Pool} from "./interfaces/v3/IUniswapV3Pool.sol";

contract V3AMO is IV3AMO, MasterAMO {
    /* ========== ERRORS ========== */
    error ExcessiveLiquidityRemoval(uint256 liquidity, uint256 unusedUsdAmount);
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

    /* ========== CONSTANTS ========== */
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint256 internal constant Q96 = 2 ** 96;
    uint256 internal constant LIQUIDITY_COEFF = 995000;
    uint24 internal constant SQRT10 = 3162278; // sqrt(10) = 3.162278


    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address pool_,
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
    function setParams(
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
        // validRemovingRatio nedds to be greater than 1 (we remove more BOOST than USD otherwise the pool is balanced )

        boostMultiplier = boostMultiplier_;
        validRangeWidth = validRangeWidth_;
        validRemovingRatio = validRemovingRatio_;
        usdUsageRatio = usdUsageRatio_;
        boostLowerPriceSell = boostLowerPriceSell_;
        boostUpperPriceBuy = boostUpperPriceBuy_;
        emit ParamsSet(
            boostMultiplier,
            validRangeWidth,
            validRemovingRatio,
            usdUsageRatio,
            boostLowerPriceSell,
            boostUpperPriceBuy
        );
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

    function _getLiquidityForUsdAmount(uint256 usdAmount) internal view returns (uint256 liquidity) {
        uint160 sqrtRatioX96;
        (sqrtRatioX96, , , ) = ISolidlyV3Pool(pool).slot0();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (uint256 amount0, uint256 amount1) = sortAmounts(type(uint128).max, usdAmount);
        liquidity = uint256(
            LiquidityAmounts.getLiquidityForAmounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1)
        );
    }

    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    ) internal override returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity) {
        liquidity = _getLiquidityForUsdAmount(usdAmount);

        // Add liquidity to the BOOST-USD pool within the specified tick range
        uint256 amount0;
        uint256 amount1;

        (amount0, amount1) = IUniswapV3Pool(pool).mint(address(this), tickLower, tickUpper, uint128(liquidity), "");

        (boostSpent, usdSpent) = sortAmounts(amount0, amount1);
        if (boostSpent < minBoostSpend || usdSpent < minUsdSpend) revert InsufficientTokenSpent();

        // Calculate valid range for USD spent based on BOOST spent and validRangeWidth
        uint256 validRange = (boostSpent * validRangeWidth) / FACTOR;
        if (toBoostAmount(usdSpent) <= boostSpent - validRange || toBoostAmount(usdSpent) >= boostSpent + validRange)
            revert InvalidRatioToAddLiquidity();

        emit AddLiquidity(boostSpent, usdSpent, liquidity);
    }

    function _unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    )
        internal
        override
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut)
    {
        (uint256 amount0Min, uint256 amount1Min) = sortAmounts(minBoostRemove, minUsdRemove);
        // Remove liquidity and store the amounts of USD and BOOST tokens received
        uint256 amount0FromBurn;
        uint256 amount1FromBurn;
        (amount0FromBurn, amount1FromBurn) = IUniswapV3Pool(pool).burn(tickLower, tickUpper, uint128(liquidity));
        (boostRemoved, usdRemoved) = sortAmounts(amount0FromBurn, amount1FromBurn);

        // Ensure the BOOST amount is greater than or equal to the USD amount
        if ((boostRemoved * validRemovingRatio) / FACTOR < toBoostAmount(usdRemoved))
            revert InvalidRatioToRemoveLiquidity();

        address feeCollector = ISolidlyV3Factory(ISolidlyV3Pool(pool).factory()).feeCollector();
        IRewardsDistributor(feeCollector).collectPoolFees(pool);
        uint128 amount0Collected;
        uint128 amount1Collected;
        (amount0Collected, amount1Collected) = IUniswapV3Pool(pool).collect(
            address(this),
            tickLower,
            tickUpper,
            type(uint128).max,
            type(uint128).max
        );
        (uint256 boostCollected, uint256 usdCollected) = sortAmounts(amount0Collected, amount1Collected);
        // Approve the transfer of usd tokens to the pool
        IERC20Upgradeable(usd).approve(pool, usdRemoved);

        // Execute the swap and store the amounts of tokens involved
        (int256 amount0, int256 amount1) = ISolidlyV3Pool(pool).swap(
            address(this),
            boost > usd, // Determines if we are swapping USD for BOOST (true) or BOOST for USD (false)
            int256(usdRemoved),
            targetSqrtPriceX96,
            minBoostAmountOut,
            deadline
        );

        // Revoke approval from the pool
        IERC20Upgradeable(usd).approve(pool, 0);

        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0, amount1);
        usdAmountIn = uint256(usdDelta);
        boostAmountOut = uint256(-boostDelta);
        // Ensure the BOOST output is sufficient relative to the USD input
        if (toUsdAmount(boostAmountOut) <= usdAmountIn)
            revert InsufficientOutputAmount({outputAmount: toUsdAmount(boostAmountOut), minRequired: usdAmountIn});
        // Check the USD usage ratio to ensure it is within limits
        if ((FACTOR * usdAmountIn) / usdRemoved < usdUsageRatio)
            revert ExcessiveLiquidityRemoval({liquidity: liquidity, unusedUsdAmount: usdRemoved - usdAmountIn});

        // // Burn the BOOST tokens collected from liquidity removal, collected owed tokens and swap
        IBoostStablecoin(boost).burn(boostCollected + boostAmountOut);

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

    function _unfarmBuyBurn() internal override returns (uint256 liquidity, uint256 newBoostPrice) {
        uint256 totalLiquidity = ISolidlyV3Pool(pool).liquidity();
        uint256 boostBalance = IERC20Upgradeable(boost).balanceOf(pool);
        uint256 usdBalance = toBoostAmount(IERC20Upgradeable(usd).balanceOf(pool)); // scaled
        if (boostBalance <= usdBalance) revert PriceNotInRange(boostPrice());

        liquidity = (totalLiquidity * (boostBalance - usdBalance)) / (boostBalance + usdBalance);
        liquidity = (liquidity * LIQUIDITY_COEFF) / FACTOR;

        _unfarmBuyBurn(
            liquidity,
            1, // minBoostRemove
            1, // minUsdRemove
            1, // minBoostAmountOut
            block.timestamp + 1 // deadline
        );

        newBoostPrice = boostPrice();
    }

    function _validateSwap(bool boostForUsd) internal view override {}

    ////////////////////////// VIEW FUNCTIONS //////////////////////////

    /**
     * @dev Calculates the boost price with precision adjustments to prevent rounding errors.
     * The function determines the price based on the relation between `boost` and `usd`,
     * while accounting for potential precision loss in mathematical operations.
     *
     * The method uses adjusted decimals and avoids direct division of large integers,
     * which can lead to significant precision loss. This ensures accurate calculations
     * and resolves previously identified issues with rounding errors in edge cases.
     *
     * @return price The calculated price of BOOST relative to USD.
     */
    function boostPrice() public view override returns (uint256 price) {
        (uint160 _sqrtPriceX96, , , ) = ISolidlyV3Pool(pool).slot0();
        uint256 sqrtPriceX96 = uint256(_sqrtPriceX96);

        // Calculate the difference in decimals between BOOST and USD
        uint8 decimalsDiff = boostDecimals - usdDecimals;

        // Adjust for decimals and square root scaling
        uint256 sqrtDecimals;
        if (decimalsDiff % 2 == 0) {
            // Even difference: scale directly
            sqrtDecimals = 10 ** (decimalsDiff / 2) * 10 ** PRICE_DECIMALS;
        } else {
            // Odd difference: handle fractional scaling with SQRT10 and FACTOR
            sqrtDecimals = (10 ** (decimalsDiff / 2) * 10 ** PRICE_DECIMALS * SQRT10) / FACTOR;
        }

        // Calculate the price based on the BOOST and USD relationship
        if (boost < usd) {
            // BOOST is less than USD: multiply the scaled price and square it
            price = ((sqrtDecimals * sqrtPriceX96) / Q96) ** 2 / 10 ** PRICE_DECIMALS;
        } else {
            // BOOST is greater than or equal to USD: adjust for inverse scaling
            price = ((sqrtDecimals * Q96) / sqrtPriceX96) ** 2 / 10 ** PRICE_DECIMALS;
        }
    }

}
