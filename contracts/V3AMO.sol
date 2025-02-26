// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "./MasterAMO.sol";
import {IQuoterV2} from "./interfaces/v3/quoter/IQuoterV2.sol";
import {IVeloQuoterV2} from "./interfaces/v3/quoter/IVeloQuoterV2.sol";
import {IAlgebraQuoter} from "./interfaces/v3/quoter/IAlgebraQuoter.sol";
import {IUniswapV3Pool} from "./interfaces/v3/IUniswapV3Pool.sol";
import {ISolidlyV3Pool} from "./interfaces/v3/ISolidlyV3Pool.sol";
import {ISolidlyV3Factory} from "./interfaces/v3/ISolidlyV3Factory.sol";
import {IRewardsDistributor} from "./interfaces/v3/IRewardsDistributor.sol";
import {IAlgebraPool} from "./interfaces/v3/IAlgebraPool.sol";
import {IAlgebraV10Pool} from "./interfaces/v3/IAlgebraV10Pool.sol";
import {IAlgebraV19Pool} from "./interfaces/v3/IAlgebraV19Pool.sol";
import {IAlgebraIntegralPool} from "./interfaces/v3/IAlgebraIntegralPool.sol";
import {IRamsesV2Pool} from "./interfaces/v3/IRamsesV2Pool.sol";
import {IV3AMO} from "./interfaces/v3/IV3AMO.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title V3AMO Contract
 * @notice Implements Automated Market Operations (AMO) for V3 pools using various DEX protocols.
 * @dev Inherits from MasterAMO and implements the IV3AMO interface.
 */
contract V3AMO is IV3AMO, MasterAMO {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // -------------------------------------------------------------
    //                         STATE VARIABLES
    // -------------------------------------------------------------

    ////// IMMUTABLE //////
    /// @inheritdoc IV3AMO
    PoolType public override poolType;
    /// @inheritdoc IV3AMO
    address public override poolCustomDeployer;
    /// @inheritdoc IV3AMO
    int24 public override tickLower;
    /// @inheritdoc IV3AMO
    int24 public override tickUpper;
    /// @inheritdoc IV3AMO
    address public override quoter;

    // -------------------------------------------------------------
    //                         INTERNAL CONSTANTS
    // -------------------------------------------------------------
    // @notice Q96 is a fixed-point scaling factor (2^96) used in Uniswap V3 calculations to represent prices in Q64.96 format.
    uint256 internal constant Q96 = 2 ** 96;
    // @notice SQRT10 is the square root of 10 scaled to 6 decimals (3.162278) used
    uint24 internal constant SQRT10 = 3162278;

    // -------------------------------------------------------------
    //                        INITIALIZATION
    // -------------------------------------------------------------
    /**
     * @notice Constructor disables initializers.
     * @dev Custom constructor for upgradeable contracts.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the V3AMO contract.
     * @param admin Address with admin privileges.
     * @param boost_ Address of the BOOST token.
     * @param usd_ Address of the USD token.
     * @param pool_ Address of the liquidity pool.
     * @param poolType_ The type of pool.
     * @param quoter_ Address of the quoter contract.
     * @param poolCustomDeployer_ Address of the custom deployer for Algebra integral pools.
     * @param boostMinter_ Address of the BOOST minter contract.
     * @param priceManager_ Address of the price manager contract.
     * @param pairedTokenType_ The paired token type.
     * @param tickLower_ Lower tick boundary.
     * @param tickUpper_ Upper tick boundary.
     * @param boostMultiplier_ Multiplier for BOOST minting.
     * @param validRangeWidth_ Valid range width for liquidity addition.
     * @param validRemovingRatio_ Valid ratio for liquidity removal.
     * @param boostLowerPriceSell_ Lower price threshold for selling BOOST.
     * @param boostUpperPriceBuy_ Upper price threshold for buying BOOST.
     */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address pool_,
        PoolType poolType_,
        address quoter_,
        address poolCustomDeployer_,
        address boostMinter_,
        address priceManager_,
        PairedTokenType pairedTokenType_,
        int24 tickLower_,
        int24 tickUpper_,
        uint256 boostMultiplier_,
        uint24 validRangeWidth_,
        uint24 validRemovingRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_
    ) public initializer {
        super.initialize(admin, boost_, usd_, pool_, boostMinter_, priceManager_, pairedTokenType_);
        poolType = poolType_;
        poolCustomDeployer = poolCustomDeployer_;

        _grantRole(SETTER_ROLE, msg.sender);
        setTickBounds(tickLower_, tickUpper_);
        setParams(
            quoter_,
            boostMultiplier_,
            validRangeWidth_,
            validRemovingRatio_,
            boostLowerPriceSell_,
            boostUpperPriceBuy_
        );
        _revokeRole(SETTER_ROLE, msg.sender);
    }

    // -------------------------------------------------------------
    //                   SETTER_ROLE ACTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IV3AMO
    function setTickBounds(int24 tickLower_, int24 tickUpper_) public override onlyRole(SETTER_ROLE) {
        tickLower = tickLower_;
        tickUpper = tickUpper_;
        emit TickBoundsSet(tickLower, tickUpper);
    }

    /// @inheritdoc IV3AMO
    function setParams(
        address quoter_,
        uint256 boostMultiplier_,
        uint24 validRangeWidth_,
        uint24 validRemovingRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_
    ) public override onlyRole(SETTER_ROLE) {
        if (validRangeWidth_ > FACTOR || validRemovingRatio_ < FACTOR) revert InvalidRatioValue();
        quoter = quoter_;
        boostMultiplier = boostMultiplier_;
        validRangeWidth = validRangeWidth_;
        validRemovingRatio = validRemovingRatio_;
        boostLowerPriceSell = boostLowerPriceSell_;
        boostUpperPriceBuy = boostUpperPriceBuy_;
        emit ParamsSet(
            quoter,
            boostMultiplier,
            validRangeWidth,
            validRemovingRatio,
            boostLowerPriceSell,
            boostUpperPriceBuy
        );
    }

    // -------------------------------------------------------------
    //                INTERNAL HELPER VIEW FUNCTIONS
    // -------------------------------------------------------------

    /**
     * @notice Internal function to calculate liquidity for a given USD amount.
     * @param usdAmount USD amount.
     * @return liquidity Calculated liquidity.
     */
    function _getLiquidityForUsdAmount(uint256 usdAmount) internal view returns (uint256 liquidity) {
        uint160 sqrtRatioX96 = _getSqrtPriceX96();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        if (usd < boost) {
            if (sqrtRatioX96 >= sqrtRatioBX96) return 0;
            return
                LiquidityAmounts.getLiquidityForAmount0(
                    uint160(Math.max(sqrtRatioX96, sqrtRatioAX96)),
                    sqrtRatioBX96,
                    usdAmount
                );
        } else {
            if (sqrtRatioX96 <= sqrtRatioAX96) return 0;
            return
                LiquidityAmounts.getLiquidityForAmount1(
                    sqrtRatioAX96,
                    uint160(Math.min(sqrtRatioX96, sqrtRatioBX96)),
                    usdAmount
                );
        }
    }

    /**
     * @notice Retrieves the current sqrt price from the pool.
     * @return _sqrtPriceX96 The sqrt price in Q64.96 format.
     */
    function _getSqrtPriceX96() internal view returns (uint160 _sqrtPriceX96) {
        bytes memory data;
        if (
            poolType == PoolType.ALGEBRA_V1_0 ||
            poolType == PoolType.ALGEBRA_V1_9 ||
            poolType == PoolType.ALGEBRA_INTEGRAL
        ) {
            (, data) = pool.staticcall(abi.encodeWithSignature("globalState()"));
        } else {
            (, data) = pool.staticcall(abi.encodeWithSignature("slot0()"));
        }
        _sqrtPriceX96 = abi.decode(data, (uint160));
    }

    /// @inheritdoc MasterAMO
    function _validateSwap(bool boostForUsd) internal view override {
        uint256 price = boostPrice();
        uint256 tp = targetPrice();
        if (boostForUsd) {
            if (price <= priceUpperBound(tp)) revert PriceAlreadyInRange(price);
        } else {
            if (price >= priceLowerBound(tp)) revert PriceAlreadyInRange(price);
        }
    }

    // -------------------------------------------------------------
    //                   INTERNAL FUNCTIONS
    // -------------------------------------------------------------

    ////// CALLBACK FUNCTIONS //////
    /**
     * @notice Internal function handling swap callbacks from various pools.
     * @param amount0Delta Change in token0 amount.
     * @param amount1Delta Change in token1 amount.
     * @param data Encoded swap type data.
     * @dev Processes swap based on SwapType. Reverts if caller is untrusted.
     */
    function _swapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) internal {
        if (msg.sender != pool) revert UntrustedCaller(msg.sender);
        uint256 boostTargetPrice = targetPrice();
        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0Delta, amount1Delta);
        SwapType swapType = abi.decode(data, (SwapType));
        if (swapType == SwapType.SELL) {
            uint256 boostAmountIn = uint256(boostDelta);
            uint256 usdAmountOut = uint256(-usdDelta);
            if (
                balanceOfToken(usd) < usdAmountOut ||
                (boostAmountIn * boostTargetPrice) / FACTOR > toBoostAmount(usdAmountOut)
            ) revert InvalidDelta();
            IMinter(boostMinter).protocolMint(pool, boostAmountIn);
        } else if (swapType == SwapType.BUY) {
            uint256 usdAmountIn = uint256(usdDelta);
            uint256 boostAmountOut = uint256(-boostDelta);
            if (
                balanceOfToken(boost) < boostAmountOut ||
                usdAmountIn > (toUsdAmount(boostAmountOut) * boostTargetPrice) / FACTOR
            ) revert InvalidDelta();
            IERC20(usd).safeTransfer(pool, usdAmountIn);
        }
    }

    /**
     * @notice Internal function handling mint callbacks.
     * @param amount0Owed Amount of token0 owed.
     * @param amount1Owed Amount of token1 owed.
     * @param data Callback data.
     */
    function _mintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) internal {
        if (msg.sender != pool) revert UntrustedCaller(msg.sender);
        (uint256 boostOwed, uint256 usdOwed) = sortAmounts(amount0Owed, amount1Owed);
        IERC20(usd).safeTransfer(pool, usdOwed);
        IMinter(boostMinter).protocolMint(pool, boostOwed);
    }

    ////// MINT-SELL-FARM FUNCTIONS //////

    /// @inheritdoc MasterAMO
    function _mintAndSellBoost(
        uint256 boostAmount
    ) internal override returns (uint256 boostAmountIn, uint256 usdAmountOut) {
        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
            address(this),
            boost < usd, // zeroForOne
            int256(boostAmount),
            targetSqrtPriceX96(),
            abi.encode(SwapType.SELL)
        );
        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0, amount1);
        boostAmountIn = uint256(boostDelta);
        usdAmountOut = uint256(-usdDelta);
        emit MintSell(boostAmountIn, usdAmountOut);
    }

    /// @inheritdoc MasterAMO
    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    ) internal override returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity) {
        liquidity = _getLiquidityForUsdAmount(usdAmount);
        uint256 amount0;
        uint256 amount1;
        if (
            poolType == PoolType.ALGEBRA_V1_0 ||
            poolType == PoolType.ALGEBRA_V1_9 ||
            poolType == PoolType.ALGEBRA_INTEGRAL
        ) {
            (amount0, amount1, ) = IAlgebraPool(pool).mint(
                address(this),
                address(this),
                tickLower,
                tickUpper,
                uint128(liquidity),
                ""
            );
        } else {
            (amount0, amount1) = IUniswapV3Pool(pool).mint(address(this), tickLower, tickUpper, uint128(liquidity), "");
        }
        (boostSpent, usdSpent) = sortAmounts(amount0, amount1);
        if (boostSpent < minBoostSpend || usdSpent < minUsdSpend) revert InsufficientTokenSpent();
        emit AddLiquidity(boostSpent, usdSpent, liquidity);
    }

    ////// UNFARM-BUY-BURN FUNCTIONS //////

    /// @inheritdoc MasterAMO
    function _unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove
    )
        internal
        override
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut)
    {
        uint256 amount0FromBurn;
        uint256 amount1FromBurn;
        if (poolType == PoolType.ALGEBRA_INTEGRAL) {
            (amount0FromBurn, amount1FromBurn) = IAlgebraIntegralPool(pool).burn(
                tickLower,
                tickUpper,
                uint128(liquidity),
                ""
            );
        } else {
            (amount0FromBurn, amount1FromBurn) = IUniswapV3Pool(pool).burn(tickLower, tickUpper, uint128(liquidity));
        }
        (boostRemoved, usdRemoved) = sortAmounts(amount0FromBurn, amount1FromBurn);
        if (boostRemoved < minBoostRemove) revert InsufficientOutputAmount(boostRemoved, minBoostRemove);
        if (usdRemoved < minUsdRemove) revert InsufficientOutputAmount(usdRemoved, minUsdRemove);

        if (poolType == PoolType.SOLIDLY_V3) {
            address feeCollector = ISolidlyV3Factory(ISolidlyV3Pool(pool).factory()).feeCollector();
            IRewardsDistributor(feeCollector).collectPoolFees(pool);
        }
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

        if ((((boostRemoved * validRemovingRatio) / FACTOR) * targetPrice()) / FACTOR < toBoostAmount(usdRemoved))
            revert InvalidRatioToRemoveLiquidity();

        (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
            address(this),
            boost > usd, // zeroForOne
            int256(usdRemoved),
            targetSqrtPriceX96(),
            abi.encode(SwapType.BUY)
        );
        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0, amount1);
        usdAmountIn = uint256(usdDelta);
        boostAmountOut = uint256(-boostDelta);

        uint256 unusedUsdAmount = usdRemoved - usdAmountIn;
        if (unusedUsdAmount > 0) _addLiquidity(unusedUsdAmount, 1, 1);

        IBoostStablecoin(boost).burn(boostCollected + boostAmountOut);

        emit UnfarmBuyBurn(
            boostRemoved,
            usdRemoved,
            liquidity,
            usdAmountIn,
            boostAmountOut,
            boostCollected - boostRemoved,
            usdCollected - usdRemoved
        );
    }

    /// @inheritdoc MasterAMO
    function _mintSellFarm() internal override returns (uint256 liquidity, uint256 newBoostPrice) {
        (, , , , liquidity) = _mintSellFarm(
            uint256(type(int256).max), // maximum BOOST amount
            1, // minBoostSpend
            1 // minUsdSpend
        );
        newBoostPrice = boostPrice();
    }

    /// @inheritdoc MasterAMO
    function _unfarmBuyBurn() internal override returns (uint256 liquidity, uint256 newBoostPrice) {
        (uint256 positionLiquidity, , ) = position();
        uint256 amountIn;
        if (poolType == PoolType.SOLIDLY_V3) {
            (int256 amount0, int256 amount1, , , ) = ISolidlyV3Pool(pool).quoteSwap(
                boost > usd,
                type(int256).max,
                targetSqrtPriceX96()
            );
            (, int256 usdDelta) = sortAmounts(amount0, amount1);
            amountIn = uint256(usdDelta);
        } else if (poolType == PoolType.CL) {
            IVeloQuoterV2.QuoteExactOutputSingleParams memory params = IVeloQuoterV2.QuoteExactOutputSingleParams({
                tokenIn: usd,
                tokenOut: boost,
                amount: uint256(type(int256).max),
                tickSpacing: IUniswapV3Pool(pool).tickSpacing(),
                sqrtPriceLimitX96: targetSqrtPriceX96()
            });
            (amountIn, , , ) = IVeloQuoterV2(quoter).quoteExactOutputSingle(params);
        } else if (poolType == PoolType.ALGEBRA_V1_0 || poolType == PoolType.ALGEBRA_V1_9) {
            (amountIn, ) = IAlgebraQuoter(quoter).quoteExactOutputSingle(
                usd,
                boost,
                uint256(type(int256).max),
                targetSqrtPriceX96()
            );
        } else if (poolType == PoolType.ALGEBRA_INTEGRAL) {
            (bool success, bytes memory data) = quoter.call(
                abi.encodeWithSignature(
                    "quoteExactOutputSingle((address,address,address,uint256,uint160))",
                    usd,
                    boost,
                    poolCustomDeployer,
                    uint256(type(int256).max),
                    targetSqrtPriceX96()
                )
            );
            if (!success)
                (, data) = quoter.call(
                    abi.encodeWithSignature(
                        "quoteExactOutputSingle((address,address,uint256,uint160))",
                        usd,
                        boost,
                        uint256(type(int256).max),
                        targetSqrtPriceX96()
                    )
                );
            (, amountIn) = abi.decode(data, (uint256, uint256));
        } else {
            IQuoterV2.QuoteExactOutputSingleParams memory params = IQuoterV2.QuoteExactOutputSingleParams({
                tokenIn: usd,
                tokenOut: boost,
                amount: uint256(type(int256).max),
                fee: IUniswapV3Pool(pool).fee(),
                sqrtPriceLimitX96: targetSqrtPriceX96()
            });
            (amountIn, , , ) = IQuoterV2(quoter).quoteExactOutputSingle(params);
        }
        liquidity = _getLiquidityForUsdAmount(amountIn);
        if (liquidity > positionLiquidity) liquidity = positionLiquidity;

        _unfarmBuyBurn(liquidity, 1, 1);
        newBoostPrice = boostPrice();
    }

    // -------------------------------------------------------------
    //                     EXTERNAL FUNCTIONS
    // -------------------------------------------------------------
    ////// SWAP-CALLBACK FUNCTIONS //////

    /**
     * @notice Callback function invoked by the Solidly V3 pool during swap operations.
     * @param amount0Delta The change in token0 amount resulting from the swap.
     * @param amount1Delta The change in token1 amount resulting from the swap.
     * @param data Encoded data containing swap type information.
     */
    function solidlyV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    /**
     * @notice Callback function invoked by the Uniswap V3 pool during swap operations.
     * @param amount0Delta The change in token0 amount resulting from the swap.
     * @param amount1Delta The change in token1 amount resulting from the swap.
     * @param data Encoded data containing swap type information.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    /**
     * @notice Callback function invoked by the Algebra pool during swap operations.
     * @param amount0Delta The change in token0 amount resulting from the swap.
     * @param amount1Delta The change in token1 amount resulting from the swap.
     * @param data Encoded data containing swap type information.
     */
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    /**
     * @notice Callback function invoked by the Ramses V2 pool during swap operations.
     * @param amount0Delta The change in token0 amount resulting from the swap.
     * @param amount1Delta The change in token1 amount resulting from the swap.
     * @param data Encoded data containing swap type information.
     */
    function ramsesV2SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    ////// MINT-CALLBACK FUNCTIONS //////

    /**
     * @notice Callback function invoked by the Solidly V3 pool during mint operations.
     * @param amount0Owed The amount of token0 owed to the pool.
     * @param amount1Owed The amount of token1 owed to the pool.
     * @param data Encoded data for the mint operation.
     */
    function solidlyV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    /**
     * @notice Callback function invoked by the Uniswap V3 pool during mint operations.
     * @param amount0Owed The amount of token0 owed to the pool.
     * @param amount1Owed The amount of token1 owed to the pool.
     * @param data Encoded data for the mint operation.
     */
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    /**
     * @notice Callback function invoked by the Algebra pool during mint operations.
     * @param amount0Owed The amount of token0 owed to the pool.
     * @param amount1Owed The amount of token1 owed to the pool.
     * @param data Encoded data for the mint operation.
     */
    function algebraMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    /**
     * @notice Callback function invoked by the Ramses V2 pool during mint operations.
     * @param amount0Owed The amount of token0 owed to the pool.
     * @param amount1Owed The amount of token1 owed to the pool.
     * @param data Encoded data for the mint operation.
     */
    function ramsesV2MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    // -------------------------------------------------------------
    //                      VIEW FUNCTIONS
    // -------------------------------------------------------------
    /**
     * @notice Calculates the current BOOST price relative to USD.
     * @return price The calculated BOOST price.
     */
    function boostPrice() public view override returns (uint256 price) {
        uint256 sqrtPriceX96 = uint256(_getSqrtPriceX96());
        uint8 decimalsDiff = boostDecimals - usdDecimals;
        uint256 sqrtDecimals;
        if (decimalsDiff % 2 == 0) {
            sqrtDecimals = 10 ** (decimalsDiff / 2) * 10 ** PRICE_DECIMALS;
        } else {
            sqrtDecimals = (10 ** (decimalsDiff / 2) * 10 ** PRICE_DECIMALS * SQRT10) / FACTOR;
        }

        if (boost < usd) {
            price = ((sqrtDecimals * sqrtPriceX96) / Q96) ** 2 / 10 ** PRICE_DECIMALS;
        } else {
            price = ((sqrtDecimals * Q96) / sqrtPriceX96) ** 2 / 10 ** PRICE_DECIMALS;
        }
    }

    /**
     * @notice Computes the target sqrt price for swapping operations.
     * @return The target sqrt price in Q64.96 format.
     */
    function targetSqrtPriceX96() public view override returns (uint160) {
        uint256 boostTargetPrice = targetPrice();
        if (usd < boost) boostTargetPrice = FACTOR ** 2 / boostTargetPrice;
        uint256 priceX96 = (boostTargetPrice * Q96 ** 2) / 10 ** PRICE_DECIMALS;
        uint8 decimalsDiff = boostDecimals - usdDecimals;
        if (boost < usd) priceX96 /= 10 ** decimalsDiff;
        else priceX96 *= 10 ** decimalsDiff;
        uint256 sqrtPriceX96 = Math.sqrt(priceX96);
        return sqrtPriceX96.toUint160();
    }

    /**
     * @notice Retrieves details of the current liquidity position.
     * @return liquidity Amount of liquidity.
     * @return boostOwed BOOST tokens owed.
     * @return usdOwed USD tokens owed.
     */
    function position() public view override returns (uint256 liquidity, uint256 boostOwed, uint256 usdOwed) {
        bytes32 key;
        if (
            poolType == PoolType.ALGEBRA_V1_0 ||
            poolType == PoolType.ALGEBRA_V1_9 ||
            poolType == PoolType.ALGEBRA_INTEGRAL
        ) {
            address owner = address(this);
            int24 bottomTick = tickLower;
            int24 topTick = tickUpper;
            assembly {
                key := or(shl(24, or(shl(24, owner), and(bottomTick, 0xFFFFFF))), and(topTick, 0xFFFFFF))
            }
        } else if (poolType == PoolType.RAMSES_V2) {
            uint256 index = 0;
            key = keccak256(abi.encodePacked(address(this), index, tickLower, tickUpper));
        } else {
            key = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        }

        uint128 _liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        if (poolType == PoolType.SOLIDLY_V3) {
            (_liquidity, tokensOwed0, tokensOwed1) = ISolidlyV3Pool(pool).positions(key);
        } else if (poolType == PoolType.ALGEBRA_V1_0) {
            (_liquidity, , , , tokensOwed0, tokensOwed1) = IAlgebraV10Pool(pool).positions(key);
        } else if (poolType == PoolType.ALGEBRA_V1_9) {
            (_liquidity, , , , tokensOwed0, tokensOwed1) = IAlgebraV19Pool(pool).positions(key);
        } else if (poolType == PoolType.ALGEBRA_INTEGRAL) {
            (liquidity, , , tokensOwed0, tokensOwed1) = IAlgebraIntegralPool(pool).positions(key);
        } else if (poolType == PoolType.RAMSES_V2) {
            (_liquidity, , , tokensOwed0, tokensOwed1, ) = IRamsesV2Pool(pool).positions(key);
        } else {
            (_liquidity, , , tokensOwed0, tokensOwed1) = IUniswapV3Pool(pool).positions(key);
        }
        if (_liquidity > 0) liquidity = uint256(_liquidity);
        (boostOwed, usdOwed) = sortAmounts(uint256(tokensOwed0), uint256(tokensOwed1));
    }
}
