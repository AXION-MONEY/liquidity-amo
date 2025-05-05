// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "./MasterAMO.sol";
import {IUniswapV3Pool} from "./interfaces/v3/IUniswapV3Pool.sol";
import {ISolidlyV3Pool} from "./interfaces/v3/ISolidlyV3Pool.sol";
import {ISolidlyV3Factory} from "./interfaces/v3/ISolidlyV3Factory.sol";
import {IRewardsDistributor} from "./interfaces/v3/IRewardsDistributor.sol";
import {IAlgebraPool} from "./interfaces/v3/IAlgebraPool.sol";
import {IAlgebraIntegralPool} from "./interfaces/v3/IAlgebraIntegralPool.sol";
import {IV3AMO} from "./interfaces/IV3AMO.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IIon} from "./interfaces/IIon.sol";

/**
 * @title V3AMO Contract
 * @notice Implements Automated Market Operations (AMO) for V3 pools using various DEX protocols.
 * @dev Inherits from MasterAMO and implements the IV3AMO interface.
 */
contract V3AMO is IV3AMO, MasterAMO {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using SafeCast for uint256;

    // -------------------------------------------------------------
    //                         STATE VARIABLES
    // -------------------------------------------------------------

    ////// IMMUTABLE //////
    /// @inheritdoc IV3AMO
    PoolType public override poolType;
    /// @inheritdoc IV3AMO
    address public override poolCustomDeployer;

    ////// MUTABLE //////
    /// @inheritdoc IV3AMO
    int24 public override tickLower;
    /// @inheritdoc IV3AMO
    int24 public override tickUpper;

    // -------------------------------------------------------------
    //                         INTERNAL CONSTANTS
    // -------------------------------------------------------------
    // @notice Q96 is a fixed-point scaling factor (2^96) used in Uniswap V3 calculations.
    uint256 internal constant Q96 = 2 ** 96;
    // @notice SQRT10 is the square root of 10 scaled to 6 decimals (3.162278) used.
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
     * @param ionAddress_ Address of the ION Stable token.
     * @param pairTokenAddress_ Address of the pair token.
     * @param poolAddress_ Address of the liquidity pool.
     * @param poolType_ The type of pool.
     * @param poolCustomDeployer_ Address of the custom deployer for Algebra integral pools.
     * @param ionMinterAddress_ Address of the ION minter contract.
     * @param priceManagerAddress_ Address of the price manager contract.
     * @param pairTokenType_ The type of the token paired with ION.
     * @param tickLower_ Lower tick boundary.
     * @param tickUpper_ Upper tick boundary.
     * @param validRangeWidth_ The valid range width for liquidity addition.
     * @param sellRatio_ The sell ratio as mintSellFarm's swap ratio.
     * @param buyRatio_ The buy ratio as unfarmBuyBurn's swap ratio.
     * @param sellIonRatioLimit_ The ratio limit for ION amount to sell.
     * @param removeLiquidityRatioLimit_ The ratio limit for liquidity to remove.
     * @param periodDuration_ The period duration (using for amounts limit).
     */
    function initialize(
        address admin,
        address ionAddress_,
        address pairTokenAddress_,
        address poolAddress_,
        PoolType poolType_,
        address poolCustomDeployer_,
        address ionMinterAddress_,
        address priceManagerAddress_,
        IPriceManager.TokenType pairTokenType_,
        int24 tickLower_,
        int24 tickUpper_,
        uint24 validRangeWidth_,
        uint24 sellRatio_,
        uint24 buyRatio_,
        uint24 sellIonRatioLimit_,
        uint24 removeLiquidityRatioLimit_,
        uint256 periodDuration_
    ) public initializer {
        super.initialize(
            admin,
            ionAddress_,
            pairTokenAddress_,
            poolAddress_,
            ionMinterAddress_,
            priceManagerAddress_,
            pairTokenType_,
            validRangeWidth_,
            sellRatio_,
            buyRatio_,
            sellIonRatioLimit_,
            removeLiquidityRatioLimit_,
            periodDuration_
        );
        poolType = poolType_;
        poolCustomDeployer = poolCustomDeployer_;

        _grantRole(SETTER_ROLE, msg.sender);
        setTickBounds(tickLower_, tickUpper_);
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

    // -------------------------------------------------------------
    //                INTERNAL HELPER VIEW FUNCTIONS
    // -------------------------------------------------------------

    /**
     * @notice Returns the current amount of liquidity held in the position.
     * @return liquidity The amount of liquidity owned in the position.
     */
    function _getPositionLiquidity() internal view returns (uint256 liquidity) {
        bytes32 key;
        if (poolType == PoolType.ALGEBRA_V1 || poolType == PoolType.ALGEBRA_INTEGRAL) {
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
        (, bytes memory data) = poolAddress.staticcall(abi.encodeWithSignature("positions(bytes32)", key));
        liquidity = poolType == PoolType.ALGEBRA_INTEGRAL ? abi.decode(data, (uint256)) : abi.decode(data, (uint128));
    }

    /**
     * @notice Internal function to calculate liquidity for a given pairToken Amount.
     * @param pairTokenAmount pairToken amount.
     * @return liquidity Calculated liquidity.
     */
    function _getLiquidityForPairTokenAmount(uint256 pairTokenAmount) internal view returns (uint256 liquidity) {
        uint160 sqrtRatioX96 = _getSqrtPriceX96();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        if (pairTokenAddress < ionAddress) {
            if (sqrtRatioX96 >= sqrtRatioBX96) return 0;
            return
                LiquidityAmounts.getLiquidityForAmount0(
                    uint160(Math.max(sqrtRatioX96, sqrtRatioAX96)),
                    sqrtRatioBX96,
                    pairTokenAmount
                );
        } else {
            if (sqrtRatioX96 <= sqrtRatioAX96) return 0;
            return
                LiquidityAmounts.getLiquidityForAmount1(
                    sqrtRatioAX96,
                    uint160(Math.min(sqrtRatioX96, sqrtRatioBX96)),
                    pairTokenAmount
                );
        }
    }

    /**
     * @notice Retrieves the current sqrt price from the pool.
     * @return _sqrtPriceX96 The sqrt price in Q64.96 format.
     */
    function _getSqrtPriceX96() internal view returns (uint160 _sqrtPriceX96) {
        bytes memory data;
        if (poolType == PoolType.ALGEBRA_V1 || poolType == PoolType.ALGEBRA_INTEGRAL) {
            (, data) = poolAddress.staticcall(abi.encodeWithSignature("globalState()"));
        } else {
            (, data) = poolAddress.staticcall(abi.encodeWithSignature("slot0()"));
        }
        _sqrtPriceX96 = abi.decode(data, (uint160));
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
        // Verify that the caller is the expected pool.
        if (msg.sender != poolAddress) {
            revert UntrustedCaller(msg.sender);
        }

        // Retrieve the current target price for ION.
        uint256 targetPrice = ionTargetPriceInPairToken();

        // Order the amounts so that ionDelta corresponds to ION token and pairTokenDelta to the pair token.
        (int256 ionDelta, int256 pairTokenDelta) = orderAmountsByTokenAddress(amount0Delta, amount1Delta);

        // Decode the swap type from the callback data.
        SwapType swapType = abi.decode(data, (SwapType));

        if (swapType == SwapType.QUOTE) {
            // For a QUOTE, the pair token is used as the input.
            uint256 pairTokenInputAmount = uint256(pairTokenDelta);

            // The data is decoded and reverted so the caller must catch and decode it.
            assembly ("memory-safe") {
                let ptr := mload(0x40)
                mstore(ptr, timestamp())
                mstore(add(ptr, 0x20), pairTokenInputAmount)
                revert(ptr, 64)
            }
        } else if (swapType == SwapType.SELL) {
            // For a SELL, ION is the input token and pair token is the output.
            uint256 ionInputAmount = uint256(ionDelta);
            uint256 pairTokenOutputAmount = uint256(-pairTokenDelta);

            // Validate that the pool has enough pair tokens and that price slippage is within allowed bounds.
            bool insufficientPairTokenBalance = balanceOfToken(pairTokenAddress) < pairTokenOutputAmount;
            bool priceSlippageExceeded = scalePairTokenToIonDecimals(pairTokenOutputAmount) <
                ionInputAmount.mulDiv(targetPrice, SCALED_UNIT);
            if (insufficientPairTokenBalance || priceSlippageExceeded) {
                revert InvalidDelta();
            }
            // Mint ION tokens to the pool as part of the swap.
            IMinter(ionMinterAddress).protocolMint(poolAddress, ionInputAmount);
        } else if (swapType == SwapType.BUY) {
            // For a BUY, the pair token is used as the input and ION as the output.
            uint256 pairTokenInputAmount = uint256(pairTokenDelta);
            uint256 ionOutputAmount = uint256(-ionDelta);

            // Validate that the pool has enough ION tokens and that the input amount is within allowed price bounds.
            bool insufficientIonBalance = balanceOfToken(ionAddress) < ionOutputAmount;
            bool priceExceeded = scalePairTokenToIonDecimals(pairTokenInputAmount) >
                ionOutputAmount.mulDiv(targetPrice, SCALED_UNIT);
            if (insufficientIonBalance || priceExceeded) {
                revert InvalidDelta();
            }
            // Transfer pair tokens to the pool to complete the swap.
            IERC20(pairTokenAddress).safeTransfer(poolAddress, pairTokenInputAmount);
        }
    }

    /**
     * @notice Internal function handling mint callbacks.
     * @param amount0Owed Amount of token0 owed.
     * @param amount1Owed Amount of token1 owed.
     */
    function _mintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata /* data */) internal {
        if (msg.sender != poolAddress) revert UntrustedCaller(msg.sender);
        (uint256 ionOwed, uint256 pairTokenOwed) = orderAmountsByTokenAddress(amount0Owed, amount1Owed);
        IERC20(pairTokenAddress).safeTransfer(poolAddress, pairTokenOwed);
        IMinter(ionMinterAddress).protocolMint(poolAddress, ionOwed);
    }

    ////// MINT-SELL-FARM FUNCTIONS //////

    /// @inheritdoc MasterAMO
    function _mintAndSell(uint24 swapRatio) internal override returns (uint256 postOperationIonPrice) {
        uint256 targetPrice = ionTargetPriceInPairToken();
        uint256 priceDelta = ionPriceInPairToken() - targetPrice;
        targetPrice += priceDelta.mulDiv((SCALED_UNIT - swapRatio), SCALED_UNIT);

        // Ensure that the AmountAtPeriod is initialized for this period, before swapping.
        increaseSoldIon(0);

        int256 amountSpecified;
        if (hasRole(OPERATOR_ROLE, msg.sender)) {
            amountSpecified = type(int256).max;
        } else {
            amountSpecified = periodAllowedIonToSell().toInt256();
        }
        (int256 amount0, int256 amount1) = IUniswapV3Pool(poolAddress).swap(
            address(this),
            ionAddress < pairTokenAddress, // zeroForOne
            amountSpecified,
            toSqrtPriceX96(targetPrice),
            abi.encode(SwapType.SELL)
        );
        (int256 ionDelta, int256 pairTokenDelta) = orderAmountsByTokenAddress(amount0, amount1);
        uint256 ionAmountIn = uint256(ionDelta);
        uint256 pairTokenAmountOut = uint256(-pairTokenDelta);

        increaseSoldIon(ionAmountIn);

        postOperationIonPrice = ionPriceInPairToken();
        emit MintSell(ionAmountIn, pairTokenAmountOut);
    }

    /// @inheritdoc MasterAMO
    function _addLiquidity(uint256 pairTokenAmount) internal override returns (uint256 liquidity) {
        liquidity = _getLiquidityForPairTokenAmount(pairTokenAmount);
        uint256 amount0;
        uint256 amount1;
        if (poolType == PoolType.ALGEBRA_V1 || poolType == PoolType.ALGEBRA_INTEGRAL) {
            (amount0, amount1, ) = IAlgebraPool(poolAddress).mint(
                address(this),
                address(this),
                tickLower,
                tickUpper,
                uint128(liquidity),
                ""
            );
        } else {
            (amount0, amount1) = IUniswapV3Pool(poolAddress).mint(
                address(this),
                tickLower,
                tickUpper,
                uint128(liquidity),
                ""
            );
        }

        (uint256 ionSpent, uint256 pairTokenSpent) = orderAmountsByTokenAddress(amount0, amount1);

        emit AddLiquidity(ionSpent, pairTokenSpent, liquidity);
    }

    ////// UNFARM-BUY-BURN FUNCTIONS //////

    /// @inheritdoc MasterAMO
    function _removeLiquidity(
        uint256 liquidity
    )
        internal
        override
        returns (uint256 ionRemoved, uint256 pairTokenRemoved, uint256 ionCollectedFee, uint256 pairTokenCollectedFee)
    {
        uint256 amount0FromBurn;
        uint256 amount1FromBurn;
        if (poolType == PoolType.ALGEBRA_INTEGRAL) {
            (amount0FromBurn, amount1FromBurn) = IAlgebraIntegralPool(poolAddress).burn(
                tickLower,
                tickUpper,
                uint128(liquidity),
                ""
            );
        } else {
            (amount0FromBurn, amount1FromBurn) = IUniswapV3Pool(poolAddress).burn(
                tickLower,
                tickUpper,
                uint128(liquidity)
            );
        }
        (ionRemoved, pairTokenRemoved) = orderAmountsByTokenAddress(amount0FromBurn, amount1FromBurn);

        if (poolType == PoolType.SOLIDLY_V3) {
            address feeCollector = ISolidlyV3Factory(ISolidlyV3Pool(poolAddress).factory()).feeCollector();
            IRewardsDistributor(feeCollector).collectPoolFees(poolAddress);
        }
        uint128 amount0Collected;
        uint128 amount1Collected;
        (amount0Collected, amount1Collected) = IUniswapV3Pool(poolAddress).collect(
            address(this),
            tickLower,
            tickUpper,
            type(uint128).max,
            type(uint128).max
        );
        (uint256 ionCollected, uint256 pairTokenCollected) = orderAmountsByTokenAddress(
            amount0Collected,
            amount1Collected
        );
        ionCollectedFee = ionCollected - ionRemoved;
        pairTokenCollectedFee = pairTokenCollected - pairTokenRemoved;
    }

    function _calculateLiquidityToUnfarm(
        uint24 swapRatio
    ) internal returns (uint256 liquidity, uint160 sqrtPriceLimitX96) {
        uint256 positionLiquidity = _getPositionLiquidity();
        uint256 targetPrice = ionTargetPriceInPairToken();
        uint256 priceDelta = targetPrice - ionPriceInPairToken();
        targetPrice -= priceDelta.mulDiv((SCALED_UNIT - swapRatio), SCALED_UNIT);
        sqrtPriceLimitX96 = toSqrtPriceX96(targetPrice);
        try
            IUniswapV3Pool(poolAddress).swap(
                address(this),
                ionAddress > pairTokenAddress, // zeroForOne
                type(int256).max,
                sqrtPriceLimitX96,
                abi.encode(SwapType.QUOTE)
            )
        {} catch (bytes memory reason) {
            // Catch and decode the quoted data (block timestamp and pair token input amount).
            require(reason.length == 64);
            (uint256 timestamp, uint256 amountIn) = abi.decode(reason, (uint256, uint256));
            // Timestamp is used for data validation.
            require(timestamp == block.timestamp);
            liquidity = _getLiquidityForPairTokenAmount(amountIn);
        }
        if (liquidity > positionLiquidity) liquidity = positionLiquidity;
    }

    /// @inheritdoc MasterAMO
    function _unfarmBuyBurn(
        uint24 swapRatio
    ) internal override returns (uint256 liquidity, uint256 postOperationIonPrice) {
        uint160 sqrtPriceLimitX96;
        (liquidity, sqrtPriceLimitX96) = _calculateLiquidityToUnfarm(swapRatio);

        if (!hasRole(OPERATOR_ROLE, msg.sender)) {
            liquidity = Math.min(liquidity, periodAllowedLiquidityToRemove());
        }
        increaseRemovedLiquidity(liquidity);
        (
            uint256 ionRemoved,
            uint256 pairTokenRemoved,
            uint256 ionCollectedFee,
            uint256 pairTokenCollectedFee
        ) = _removeLiquidity(liquidity);

        (int256 amount0, int256 amount1) = IUniswapV3Pool(poolAddress).swap(
            address(this),
            ionAddress > pairTokenAddress, // zeroForOne
            int256(pairTokenRemoved),
            sqrtPriceLimitX96,
            abi.encode(SwapType.BUY)
        );
        (int256 ionDelta, int256 pairTokenDelta) = orderAmountsByTokenAddress(amount0, amount1);
        uint256 pairTokenAmountIn = uint256(pairTokenDelta);
        uint256 ionAmountOut = uint256(-ionDelta);

        uint256 remainedPairTokenAfterOperation = pairTokenRemoved - pairTokenAmountIn;
        if (remainedPairTokenAfterOperation > 0) {
            uint256 addedLiquidity = _addLiquidity(remainedPairTokenAfterOperation);
            lastPeriodAmounts.removedLiquidity -= addedLiquidity;
            liquidity -= addedLiquidity;
        }

        IIon(ionAddress).burn(ionCollectedFee + ionRemoved + ionAmountOut);
        postOperationIonPrice = ionPriceInPairToken();
        emit UnfarmBuyBurn(
            ionRemoved,
            pairTokenRemoved,
            liquidity,
            pairTokenAmountIn,
            ionAmountOut,
            ionCollectedFee,
            pairTokenCollectedFee
        );
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
    /// @inheritdoc IMasterAMO
    function ionPriceInPairToken() public view override returns (uint256 price) {
        uint256 sqrtPriceX96 = uint256(_getSqrtPriceX96());
        uint8 decimalsDiff = ionDecimals - pairTokenDecimals;
        uint256 sqrtDecimals;
        if (decimalsDiff % 2 == 0) {
            sqrtDecimals = 10 ** (decimalsDiff / 2) * 10 ** PRICE_DECIMALS;
        } else {
            sqrtDecimals = (10 ** (decimalsDiff / 2) * 10 ** PRICE_DECIMALS * SQRT10) / SCALED_UNIT;
        }

        if (ionAddress < pairTokenAddress) {
            price = ((sqrtDecimals * sqrtPriceX96) / Q96) ** 2 / 10 ** PRICE_DECIMALS;
        } else {
            price = ((sqrtDecimals * Q96) / sqrtPriceX96) ** 2 / 10 ** PRICE_DECIMALS;
        }
    }

    /// @inheritdoc IV3AMO
    function toSqrtPriceX96(uint256 price) public view override returns (uint160) {
        if (pairTokenAddress < ionAddress) price = SCALED_UNIT ** 2 / price;
        uint256 priceX96 = (price * Q96 ** 2) / 10 ** PRICE_DECIMALS;
        uint8 decimalsDiff = ionDecimals - pairTokenDecimals;
        if (ionAddress < pairTokenAddress) priceX96 /= 10 ** decimalsDiff;
        else priceX96 *= 10 ** decimalsDiff;
        uint256 sqrtPriceX96 = Math.sqrt(priceX96);
        return sqrtPriceX96.toUint160();
    }

    /// @inheritdoc IMasterAMO
    function getOwnedTokens()
        public
        view
        override
        returns (uint256 liquidityOwned, uint256 ionOwned, uint256 pairTokenOwned)
    {
        liquidityOwned = _getPositionLiquidity();
        uint160 sqrtRatioX96 = _getSqrtPriceX96();
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidityOwned.toUint128()
        );
        (ionOwned, pairTokenOwned) = orderAmountsByTokenAddress(amount0, amount1);
    }
}
