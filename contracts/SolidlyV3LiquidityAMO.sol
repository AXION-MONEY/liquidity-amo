// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./interfaces/v3/ISolidlyV3LiquidityAMO.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";
import {ISolidlyV3Pool} from "./interfaces/v3/ISolidlyV3Pool.sol";

/// @title Liquidity AMO for BOOST-USD Solidly pair
/// @notice The SolidlyV3LiquidityAMO contract is responsible for maintaining the BOOST-USD peg in Solidly pairs. It achieves
/// this through minting and burning BOOST tokens, as well as adding and removing liquidity from the BOOST-USD pair.
contract SolidlyV3LiquidityAMO is
    ISolidlyV3LiquidityAMO,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== ERRORS ========== */
    error ZeroAddress();
    error InvalidRatioValue();
    error InsufficientOutputAmount(uint256 outputAmount, uint256 minRequired);
    error InvalidRatioToAddLiquidity();
    error InvalidRatioToRemoveLiquidity();
    error ExcessiveLiquidityRemoval(uint256 liquidity, uint256 unusedUsdAmount);
    error PriceNotInRange(uint256 price);
    error InvalidFactorValue();

    /* ========== ROLES ========== */
    bytes32 public constant override SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant override AMO_ROLE = keccak256("AMO_ROLE");
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant override WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /* ========== VARIABLES ========== */
    address public override boost;
    address public override usd;
    address public override pool;
    uint8 public override boostDecimals;
    uint8 public override usdDecimals;
    address public override boostMinter;

    address public override treasuryVault;
    uint256 public override boostMultiplier; // decimals 6
    uint24 public override validRangeRatio; // decimals 6
    uint24 public override validRemovingRatio; // decimals 6
    uint24 public override dryPowderRatio; // decimals 6
    uint24 public override usdUsageRatio; // decimals 6
    int24 public override tickLower;
    int24 public override tickUpper;
    uint160 public override targetSqrtPriceX96;

    uint256 public boostLowerPriceSell; // decimals 6
    uint256 public boostUpperPriceBuy; // decimals 6

    /* ========== CONSTANTS ========== */
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint256 internal constant Q96 = 2 ** 96;
    uint8 internal constant PRICE_DECIMALS = 6;
    uint8 internal constant PARAMS_DECIMALS = 6;
    uint256 internal constant FACTOR = 10 ** PARAMS_DECIMALS;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address pool_,
        address boostMinter_,
        address treasuryVault_,
        int24 tickLower_,
        int24 tickUpper_,
        uint160 targetSqrtPriceX96_,
        uint256 boostMultiplier_,
        uint24 validRangeRatio_,
        uint24 validRemovingRatio_,
        uint24 dryPowderRatio_,
        uint24 usdUsageRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        if (
            admin == address(0) ||
            boost_ == address(0) ||
            usd_ == address(0) ||
            pool_ == address(0) ||
            boostMinter_ == address(0)
        ) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        boost = boost_;
        usd = usd_;
        pool = pool_;
        boostDecimals = IERC20Metadata(boost).decimals();
        usdDecimals = IERC20Metadata(usd).decimals();
        boostMinter = boostMinter_;

        _grantRole(SETTER_ROLE, address(this));
        this.setVault(treasuryVault_);
        this.setTickBounds(tickLower_, tickUpper_);
        this.setTargetSqrtPriceX96(targetSqrtPriceX96_);
        this.setParams(
            boostMultiplier_,
            validRangeRatio_,
            validRemovingRatio_,
            dryPowderRatio_,
            usdUsageRatio_,
            boostLowerPriceSell_,
            boostUpperPriceBuy_
        );
        _revokeRole(SETTER_ROLE, address(this));
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////

    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external override onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// SETTER_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function setParams(
        uint256 boostMultiplier_,
        uint24 validRangeRatio_,
        uint24 validRemovingRatio_,
        uint24 dryPowderRatio_,
        uint24 usdUsageRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_
    ) external override onlyRole(SETTER_ROLE) {
        if (
            validRangeRatio_ > FACTOR ||
            validRemovingRatio_ > FACTOR ||
            dryPowderRatio_ > FACTOR ||
            usdUsageRatio_ > FACTOR
        ) revert InvalidRatioValue();
        boostMultiplier = boostMultiplier_;
        validRangeRatio = validRangeRatio_;
        validRemovingRatio = validRemovingRatio_;
        dryPowderRatio = dryPowderRatio_;
        usdUsageRatio = usdUsageRatio_;
        boostLowerPriceSell = boostLowerPriceSell_;
        boostUpperPriceBuy = boostUpperPriceBuy_;
        emit ParamsSet(
            boostMultiplier,
            validRangeRatio,
            validRemovingRatio,
            dryPowderRatio,
            usdUsageRatio,
            boostLowerPriceSell,
            boostUpperPriceBuy
        );
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function setVault(address treasuryVault_) external override onlyRole(SETTER_ROLE) {
        if (treasuryVault_ == address(0)) revert ZeroAddress();
        treasuryVault = treasuryVault_;
        emit VaultSet(treasuryVault);
    }

    function setTickBounds(int24 tickLower_, int24 tickUpper_) external override onlyRole(SETTER_ROLE) {
        tickLower = tickLower_;
        tickUpper = tickUpper_;
        emit TickBoundsSet(tickLower, tickUpper);
    }

    function setTargetSqrtPriceX96(uint160 targetSqrtPriceX96_) external override onlyRole(SETTER_ROLE) {
        if (targetSqrtPriceX96_ <= MIN_SQRT_RATIO || targetSqrtPriceX96_ >= MAX_SQRT_RATIO) revert InvalidRatioValue();
        targetSqrtPriceX96 = targetSqrtPriceX96_;
        emit TargetSqrtPriceX96Set(targetSqrtPriceX96);
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    function _mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) internal returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 dryPowderAmount) {
        // Mint the specified amount of BOOST tokens
        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of BOOST tokens to the pool
        IERC20Upgradeable(boost).approve(pool, boostAmount);

        // Execute the swap
        (int256 amount0, int256 amount1) = ISolidlyV3Pool(pool).swap(
            address(this),
            boost < usd,
            int256(boostAmount),
            targetSqrtPriceX96,
            minUsdAmountOut,
            deadline
        );

        // Revoke approval from the pool
        IERC20Upgradeable(boost).approve(pool, 0);

        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0, amount1);
        boostAmountIn = uint256(boostDelta);
        usdAmountOut = uint256(-usdDelta);
        if (toBoostAmount(usdAmountOut) <= boostAmountIn)
            revert InsufficientOutputAmount({outputAmount: toBoostAmount(usdAmountOut), minRequired: boostAmountIn});

        dryPowderAmount = (usdAmountOut * dryPowderRatio) / FACTOR;
        // Transfer the dry powder USD to the treasury
        IERC20Upgradeable(usd).safeTransfer(treasuryVault, dryPowderAmount);

        // Burn excessive boosts
        if (boostAmount > boostAmountIn) IBoostStablecoin(boost).burn(boostAmount - boostAmountIn);

        // Emit events for minting BOOST tokens and executing the swap
        emit MintBoost(boostAmountIn);
        emit Swap(boost, usd, boostAmountIn, usdAmountOut);
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 dryPowderAmount)
    {
        (boostAmountIn, usdAmountOut, dryPowderAmount) = _mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);
    }

    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    ) internal returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity) {
        // Mint the specified amount of BOOST tokens
        uint256 boostAmount = (toBoostAmount(usdAmount) * boostMultiplier) / FACTOR;

        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of BOOST and USD tokens to the pool
        IERC20Upgradeable(boost).approve(pool, boostAmount);
        IERC20Upgradeable(usd).approve(pool, usdAmount);

        (uint256 amount0Min, uint256 amount1Min) = sortAmounts(minBoostSpend, minUsdSpend);
        liquidity = liquidityForUsd(usdAmount);
        // Add liquidity to the BOOST-USD pool
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

        // Calculate the valid range for USD spent based on the BOOST spent and the validRangeRatio
        uint256 validRange = (boostSpent * validRangeRatio) / FACTOR;
        if (toBoostAmount(usdSpent) <= boostSpent - validRange || toBoostAmount(usdSpent) >= boostSpent + validRange)
            revert InvalidRatioToAddLiquidity();

        // Burn excessive boosts
        if (boostAmount > boostSpent) IBoostStablecoin(boost).burn(boostAmount - boostSpent);

        // Emit event for adding liquidity
        emit AddLiquidity(boostAmount, usdAmount, boostSpent, usdSpent, liquidity);
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        (boostSpent, usdSpent, liquidity) = _addLiquidity(usdAmount, minBoostSpend, minUsdSpend, deadline);
    }

    function _mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        internal
        returns (
            uint256 boostAmountIn,
            uint256 usdAmountOut,
            uint256 dryPowderAmount,
            uint256 boostSpent,
            uint256 usdSpent,
            uint256 liquidity
        )
    {
        (boostAmountIn, usdAmountOut, dryPowderAmount) = _mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);

        uint256 price = boostPrice();
        if (price > FACTOR - validRangeRatio && price < FACTOR + validRangeRatio) {
            uint256 usdBalance = IERC20Upgradeable(usd).balanceOf(address(this));
            (boostSpent, usdSpent, liquidity) = _addLiquidity(usdBalance, minBoostSpend, minUsdSpend, deadline);
        }
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (
            uint256 boostAmountIn,
            uint256 usdAmountOut,
            uint256 dryPowderAmount,
            uint256 boostSpent,
            uint256 usdSpent,
            uint256 liquidity
        )
    {
        (boostAmountIn, usdAmountOut, dryPowderAmount, boostSpent, usdSpent, liquidity) = _mintSellFarm(
            boostAmount,
            minUsdAmountOut,
            minBoostSpend,
            minUsdSpend,
            deadline
        );
    }

    function _unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    ) internal returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut) {
        (uint256 amount0Min, uint256 amount1Min) = sortAmounts(minBoostRemove, minUsdRemove);
        // Remove liquidity and store the amounts of USD and BOOST tokens received
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
                deadline
            );
        (boostRemoved, usdRemoved) = sortAmounts(amount0FromBurn, amount1FromBurn);
        (uint256 boostCollected, uint256 usdCollected) = sortAmounts(amount0Collected, amount1Collected);

        // Ensure the BOOST amount is greater than or equal to the USD amount
        if ((boostRemoved * validRemovingRatio) / FACTOR < toBoostAmount(usdRemoved))
            revert InvalidRatioToRemoveLiquidity();

        // Approve the transfer of usd tokens to the pool
        IERC20Upgradeable(usd).approve(pool, usdRemoved);

        // Execute the swap and store the amounts of tokens involved
        (int256 amount0, int256 amount1) = ISolidlyV3Pool(pool).swap(
            address(this),
            boost > usd,
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
        if (toUsdAmount(boostAmountOut) <= usdAmountIn)
            revert InsufficientOutputAmount({outputAmount: toUsdAmount(boostAmountOut), minRequired: usdAmountIn});

        if ((FACTOR * usdAmountIn) / usdRemoved < usdUsageRatio)
            revert ExcessiveLiquidityRemoval({liquidity: liquidity, unusedUsdAmount: usdRemoved - usdAmountIn});

        // Burn the BOOST tokens received from burn liquidity, collect owed tokens and swap
        IBoostStablecoin(boost).burn(boostCollected + boostAmountOut);

        // Emit events for removing liquidity, burning BOOST tokens, and executing the swap
        emit RemoveLiquidity(minBoostRemove, minUsdRemove, boostRemoved, usdRemoved, liquidity);
        emit CollectOwedTokens(boostCollected - boostRemoved, usdCollected - usdRemoved);
        emit Swap(usd, boost, usdAmountIn, boostAmountOut);
        emit BurnBoost(boostCollected + boostAmountOut);
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut)
    {
        (boostRemoved, usdRemoved, usdAmountIn, boostAmountOut) = _unfarmBuyBurn(
            liquidity,
            minBoostRemove,
            minUsdRemove,
            minBoostAmountOut,
            deadline
        );
    }

    ////////////////////////// PUBLIC FUNCTIONS //////////////////////////
    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function mintSellFarm() external whenNotPaused nonReentrant returns (uint256 liquidity, uint256 newBoostPrice) {
        uint256 maxBoostAmount = IERC20Upgradeable(boost).balanceOf(pool);
        bool zeroForOne = boost < usd;
        (int256 amount0, int256 amount1, , , ) = ISolidlyV3Pool(pool).quoteSwap(
            zeroForOne,
            int256(maxBoostAmount),
            targetSqrtPriceX96
        );
        uint256 boostAmount;
        if (zeroForOne) boostAmount = uint256(amount0);
        else boostAmount = uint256(amount1);

        (, , , , , liquidity) = _mintSellFarm(
            boostAmount,
            1, // minUsdAmountOut
            1, // minBoostSpend
            1, // minUsdSpend
            block.timestamp + 1 // deadline
        );

        newBoostPrice = boostPrice();

        // Checks if the actual average price of boost when selling is greater than the boostLowerPriceSell
        if (newBoostPrice < boostLowerPriceSell) revert PriceNotInRange(newBoostPrice);

        emit PublicMintSellFarmExecuted(liquidity, newBoostPrice);
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function unfarmBuyBurn(
        uint24 liquidityFactor
    ) external whenNotPaused nonReentrant returns (uint256 liquidity, uint256 newBoostPrice) {
        // Check liquidity factor
        if (liquidityFactor > FACTOR) revert InvalidFactorValue();

        uint256 totalLiquidity = ISolidlyV3Pool(pool).liquidity();
        uint256 boostBalance = IERC20Upgradeable(boost).balanceOf(pool);
        uint256 usdBalance = toBoostAmount(IERC20Upgradeable(usd).balanceOf(pool)); // scaled
        if (boostBalance <= usdBalance) revert PriceNotInRange(boostPrice());

        liquidity = (totalLiquidity * (boostBalance - usdBalance)) / (boostBalance + usdBalance);
        liquidity = (liquidity * liquidityFactor) / FACTOR;

        _unfarmBuyBurn(
            liquidity,
            1, // minBoostRemove
            1, // minUsdRemove
            1, // minBoostAmountOut
            block.timestamp + 1 // deadline
        );

        newBoostPrice = boostPrice();

        // Checks if the actual average price of boost when buying is less than the boostUpperPriceBuy
        if (newBoostPrice > boostUpperPriceBuy) revert PriceNotInRange(newBoostPrice);

        emit PublicUnfarmBuyBurnExecuted(liquidity, newBoostPrice);
    }

    ////////////////////////// Withdrawal functions //////////////////////////
    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function withdrawERC20(address token, uint256 amount, address recipient) external onlyRole(WITHDRAWER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        IERC20Upgradeable(token).safeTransfer(recipient, amount);
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function withdrawERC721(address token, uint256 tokenId, address recipient) external onlyRole(WITHDRAWER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        IERC721Upgradeable(token).safeTransferFrom(address(this), recipient, tokenId);
    }

    ////////////////////////// Internal functions //////////////////////////
    function sortAmounts(uint256 amount0, uint256 amount1) internal view returns (uint256, uint256) {
        if (boost < usd) return (amount0, amount1);
        return (amount1, amount0);
    }

    function sortAmounts(int256 amount0, int256 amount1) internal view returns (int256, int256) {
        if (boost < usd) return (amount0, amount1);
        return (amount1, amount0);
    }

    function toBoostAmount(uint256 usdAmount) internal view returns (uint256) {
        return usdAmount * 10 ** (boostDecimals - usdDecimals);
    }

    function toUsdAmount(uint256 boostAmount) internal view returns (uint256) {
        return boostAmount / 10 ** (boostDecimals - usdDecimals);
    }

    ////////////////////////// View Functions //////////////////////////
    function position() public view returns (uint128 _liquidity, uint128 boostOwed, uint128 usdOwed) {
        bytes32 key = keccak256(abi.encodePacked(address(this), tickLower, tickUpper));
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        (_liquidity, tokensOwed0, tokensOwed1) = ISolidlyV3Pool(pool).positions(key);
        if (boost < usd) {
            boostOwed = tokensOwed0;
            usdOwed = tokensOwed1;
        } else {
            usdOwed = tokensOwed0;
            boostOwed = tokensOwed1;
        }
    }

    function liquidityForUsd(uint256 usdAmount) public view returns (uint256 liquidityAmount) {
        uint128 currentLiquidity = ISolidlyV3Pool(pool).liquidity();
        return (usdAmount * currentLiquidity) / IERC20Upgradeable(usd).balanceOf(pool);
    }

    function liquidityForBoost(uint256 boostAmount) public view returns (uint256 liquidityAmount) {
        uint128 currentLiquidity = ISolidlyV3Pool(pool).liquidity();
        return (boostAmount * currentLiquidity) / IERC20Upgradeable(boost).balanceOf(pool);
    }

    function boostPrice() public view returns (uint256 price) {
        (uint160 sqrtPriceX96, , , ) = ISolidlyV3Pool(pool).slot0();
        if (boost < usd) {
            price = (10 ** (boostDecimals - usdDecimals + PRICE_DECIMALS) * sqrtPriceX96 ** 2) / Q96 ** 2;
        } else {
            price = ((sqrtPriceX96 ** 2 / Q96 ** 2) * 10 ** PRICE_DECIMALS) / 10 ** (boostDecimals - usdDecimals);
        }
    }
}
