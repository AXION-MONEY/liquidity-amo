// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";
import {IMasterAMO} from "./interfaces/IMasterAMO.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPriceManager} from "./price-manager/interfaces/IPriceManager.sol";

/**
 * @title MasterAMO Contract
 * @notice This abstract contract provides a framework for Automated Market Operations (AMO)
 *         within the Boost stablecoin ecosystem. It facilitates operations such as minting Boost,
 *         selling it for USD, adding liquidity to a Boost-USD pool, and executing liquidity removal,
 *         buying, and burning when necessary to maintain the peg.
 *
 * @dev The contract is designed to be upgradeable via a timelock mechanism to allow future enhancements.
 *      It is pausable, and only authorized roles may execute certain operations:
 *      - DEFAULT_ADMIN_ROLE: Admin privileges.
 *      - AMO_ROLE: Executes AMO-related actions.
 *      - SETTER_ROLE: For setting critical parameters.
 *      - PAUSER_ROLE / UNPAUSER_ROLE: For pausing and unpausing contract operations.
 *      - WITHDRAWER_ROLE: For token withdrawals.
 *
 *      Future upgrades may incorporate strict governance mechanisms.
 */
abstract contract MasterAMO is
    IMasterAMO,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /* ========== ERRORS ========== */
    error ZeroAddress();
    error InvalidRatioValue();
    error InsufficientOutputAmount(uint256 outputAmount, uint256 minRequired);
    error InvalidRatioToAddLiquidity();
    error InvalidRatioToRemoveLiquidity();
    error PriceNotInRange(uint256 price);
    error PriceAlreadyInRange(uint256 price);
    error InvalidPairedTokenType();

    /* ========== EVENTS ========== */
    event MintSell(uint256 boostAmountIn, uint256 usdAmountOut);
    event PublicMintSellFarmExecuted(uint256 liquidity, uint256 newBoostPrice);
    event PublicUnfarmBuyBurnExecuted(uint256 liquidity, uint256 newBoostPrice);
    event SetTargetPricePremium(uint256 premium);

    /* ========= MODIFIERS ========= */
    /**
     * @dev Modifier to validate swap parameters.
     * @param boostForUsd A boolean indicating the swap direction: true for Boost → USD, false for USD → Boost.
     */
    modifier validateSwap(bool boostForUsd) {
        _validateSwap(boostForUsd);
        _;
    }

    /* ========== ROLES ========== */
    /// @inheritdoc IMasterAMO
    bytes32 public constant override SETTER_ROLE = keccak256("SETTER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override AMO_ROLE = keccak256("AMO_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /* ========== VARIABLES ========== */
    /// @inheritdoc IMasterAMO
    address public override boost;
    /// @inheritdoc IMasterAMO
    address public override usd;
    /// @inheritdoc IMasterAMO
    address public override pool;
    /// @inheritdoc IMasterAMO
    uint8 public override boostDecimals;
    /// @inheritdoc IMasterAMO
    uint8 public override usdDecimals;
    /// @inheritdoc IMasterAMO
    address public override boostMinter;

    address public priceManager; // # FIXME: price manager address
    PairedTokenType public pairedTokenType;

    /// @inheritdoc IMasterAMO
    uint256 public override boostMultiplier;
    /// @inheritdoc IMasterAMO
    uint24 public override validRangeWidth;
    /// @inheritdoc IMasterAMO
    uint24 public override validRemovingRatio;

    /// @inheritdoc IMasterAMO
    uint256 public override boostLowerPriceSell;
    /// @inheritdoc IMasterAMO
    uint256 public override boostUpperPriceBuy;

    // @inheritdoc IMasterAMO
    uint256 public override targetPricePremium;

    /* ========== CONSTANTS ========== */
    uint8 internal constant PRICE_DECIMALS = 6; // BOOST price decimals.
    uint8 internal constant PARAMS_DECIMALS = 6; // Internal decimals for parameter calculations.
    uint256 internal constant FACTOR = 10 ** PARAMS_DECIMALS; // Scaling factor. // # FIXME: Rename ScaledUnit
    bool internal constant SELL_BOOST = true; // Indicator for a Boost-to-USD swap.
    bool internal constant BUY_BOOST = false; // Indicator for a USD-to-Boost swap.

    /* ========== FUNCTIONS ========== */
    /**
     * @notice Initializes the MasterAMO contract.
     * @param admin Address to be granted the DEFAULT_ADMIN_ROLE.
     * @param boost_ Address of the Boost stablecoin.
     * @param usd_ Address of the USD stablecoin (e.g., USDC or USDT).
     * @param pool_ Address of the liquidity pool for the Boost-USD pair.
     * @param boostMinter_ Address of the Boost minter contract.
     * @param priceManager_ Address of the price manager contract.
     * @param pairedTokenType_ The type of token paired with Boost (e.g., STABLE, SUSDE, SFRAX, SDAI).
     * @dev Ensures no critical parameter is the zero address.
     */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address pool_,
        address boostMinter_,
        address priceManager_,
        PairedTokenType pairedTokenType_
    ) public onlyInitializing {
        __AccessControlEnumerable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

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
        priceManager = priceManager_;
        pairedTokenType = pairedTokenType_;
        targetPricePremium = 0; // Default Value to 0
    }
    ////////////////////////// SETTER ACTIONS //////////////////////////
    /**
     * @notice Sets the premium offset used in calculating the target price for staked pairs.
     * @dev The target price premium is added to the preview deposit value for staked tokens (SUSDE, SFRAX, SDAI)
     *      to compute the target price. This premium represents the allowable price slippage and must be set lower than the pull fee.
     *      Only accounts with the SETTER_ROLE are authorized to update this parameter.
     *
     * @param _targetPricePremium The new premium offset value to be applied in target price calculations.
     */
    function setTargetPricePremium(uint256 _targetPricePremium) external onlyRole(SETTER_ROLE) {
        targetPricePremium = _targetPricePremium;
        emit SetTargetPricePremium(targetPricePremium);
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////
    /// @inheritdoc IMasterAMO
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IMasterAMO
    function unpause() external override onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    /**
     * @notice Internal function to mint and sell Boost for USD.
     * @param boostAmount The amount of Boost tokens to mint.
     * @return boostAmountIn The amount of Boost tokens used in the process.
     * @return usdAmountOut The amount of USD tokens received from the sale.
     * @dev Must be implemented by a derived contract.
     */
    function _mintAndSellBoost(
        uint256 boostAmount
    ) internal virtual returns (uint256 boostAmountIn, uint256 usdAmountOut);

    /// @inheritdoc IMasterAMO
    function mintAndSellBoost(
        uint256 boostAmount
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostAmountIn, uint256 usdAmountOut)
    {
        (boostAmountIn, usdAmountOut) = _mintAndSellBoost(boostAmount);
    }

    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    ) internal virtual returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity);

    /// @inheritdoc IMasterAMO
    function addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        (boostSpent, usdSpent, liquidity) = _addLiquidity(usdAmount, minBoostSpend, minUsdSpend);
    }

    /**
     * @notice Internal function that combines minting, selling, and farming (liquidity addition).
     * @param boostAmount The amount of Boost tokens to mint.
     * @param minBoostSpend The minimum Boost tokens to spend for liquidity.
     * @param minUsdSpend The minimum USD tokens to spend for liquidity.
     * @return boostAmountIn The amount of Boost tokens used for minting and selling.
     * @return usdAmountOut The amount of USD tokens received from selling Boost.
     * @return boostSpent The amount of Boost tokens spent when adding liquidity.
     * @return usdSpent The amount of USD tokens spent when adding liquidity.
     * @return liquidity The liquidity tokens received from the pool.
     * @dev Liquidity addition is executed only if the current Boost price is within a specific range.
     */
    function _mintSellFarm(
        uint256 boostAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    )
        internal
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        (boostAmountIn, usdAmountOut) = _mintAndSellBoost(boostAmount);

        uint256 price = boostPrice();
        uint256 tp = targetPrice();
        if (price > priceLowerBound(tp) && price < priceUpperBound(tp)) {
            uint256 usdBalance = IERC20(usd).balanceOf(address(this));
            (boostSpent, usdSpent, liquidity) = _addLiquidity(usdBalance, minBoostSpend, minUsdSpend);
        }
    }

    /// @inheritdoc IMasterAMO
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        (boostAmountIn, usdAmountOut, boostSpent, usdSpent, liquidity) = _mintSellFarm(
            boostAmount,
            minBoostSpend,
            minUsdSpend
        );
    }

    /**
     * @notice Internal function to remove liquidity, buy Boost, and burn the acquired Boost.
     * @param liquidity The amount of liquidity tokens to remove.
     * @param minBoostRemove The minimum Boost tokens to remove.
     * @param minUsdRemove The minimum USD tokens to remove.
     * @return boostRemoved The amount of Boost tokens removed.
     * @return usdRemoved The amount of USD tokens removed.
     * @return usdAmountIn The USD amount used to buy Boost.
     * @return boostAmountOut The amount of Boost tokens obtained after purchase.
     * @dev Must be implemented by a derived contract.
     */
    function _unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove
    ) internal virtual returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut);

    /// @inheritdoc IMasterAMO
    function unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove
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
            minUsdRemove
        );
    }

    ////////////////////////// PUBLIC FUNCTIONS //////////////////////////
    /**
     * @notice Internal function to perform the mint, sell, and farming (liquidity addition) operations
     *         in a public context when Boost is over peg.
     * @return liquidity The liquidity tokens received.
     * @return newBoostPrice The new average price of Boost after the operation.
     * @dev Must be implemented by a derived contract.
     */
    function _mintSellFarm() internal virtual returns (uint256 liquidity, uint256 newBoostPrice);

    /**
     * @notice Public function to execute mint, sell, and farm operations when Boost is over peg.
     * @return liquidity The liquidity tokens received.
     * @return newBoostPrice The new average price of Boost after the operation.
     * @dev Validates that the resulting Boost price is not below the lower price threshold.
     *      Callable when the contract is not paused and with a validated swap (Boost → USD).
     */
    function mintSellFarm()
        external
        override
        whenNotPaused
        nonReentrant
        validateSwap(SELL_BOOST)
        returns (uint256 liquidity, uint256 newBoostPrice)
    {
        // Perform the mint and sell, and return liquidity and the new Boost price
        (liquidity, newBoostPrice) = _mintSellFarm();
        // Checks if the actual average price of boost when selling is greater than the boostLowerPriceSell
        uint256 tp = targetPrice();
        if (newBoostPrice < (tp * boostLowerPriceSell) / FACTOR) revert PriceNotInRange(newBoostPrice);

        emit PublicMintSellFarmExecuted(liquidity, newBoostPrice);
    }

    /**
     * @notice Internal function to perform the un-farming, buying, and burning operations
     *         in a public context when Boost is under peg.
     * @return liquidity The liquidity tokens affected.
     * @return newBoostPrice The new average price of Boost after the operation.
     * @dev Must be implemented by a derived contract.
     */
    function _unfarmBuyBurn() internal virtual returns (uint256 liquidity, uint256 newBoostPrice);

    /**
     * @notice Public function to execute un-farming, buying, and burning operations when Boost is under peg.
     * @return liquidity The liquidity tokens affected.
     * @return newBoostPrice The new average price of Boost after the operation.
     * @dev Validates that the resulting Boost price does not exceed the upper price threshold.
     *      Callable when the contract is not paused and with a validated swap (USD → Boost).
     */
    function unfarmBuyBurn()
        external
        override
        whenNotPaused
        nonReentrant
        validateSwap(BUY_BOOST)
        returns (uint256 liquidity, uint256 newBoostPrice)
    {
        (liquidity, newBoostPrice) = _unfarmBuyBurn();
        // Checks if the actual average price of boost when buying is less than the boostUpperPriceBuy
        uint256 tp = targetPrice();
        if (newBoostPrice > (tp * boostUpperPriceBuy) / FACTOR) revert PriceNotInRange(newBoostPrice);

        emit PublicUnfarmBuyBurnExecuted(liquidity, newBoostPrice);
    }

    ////////////////////////// WITHDRAWAL FUNCTIONS //////////////////////////
    /// @inheritdoc IMasterAMO
    function withdrawERC20(
        address token,
        uint256 amount,
        address recipient
    ) external override onlyRole(WITHDRAWER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(recipient, amount);
    }

    ////////////////////////// INTERNAL HELPER FUNCTIONS //////////////////////////
    /**
     * @notice Sorts two token amounts based on the token addresses.
     * @param amount0 The first token amount.
     * @param amount1 The second token amount.
     * @return (uint256, uint256) The sorted token amounts.
     */
    function sortAmounts(uint256 amount0, uint256 amount1) internal view returns (uint256, uint256) {
        if (boost < usd) return (amount0, amount1);
        return (amount1, amount0);
    }

    /**
     * @notice Sorts two signed token amounts based on the token addresses.
     * @param amount0 The first token amount.
     * @param amount1 The second token amount.
     * @return (int256, int256) The sorted token amounts.
     */
    function sortAmounts(int256 amount0, int256 amount1) internal view returns (int256, int256) {
        if (boost < usd) return (amount0, amount1);
        return (amount1, amount0);
    }

    /**
     * @notice Converts a USD amount to the equivalent Boost amount based on token decimals.
     * @param usdAmount The amount in USD.
     * @return The corresponding amount in Boost.
     */
    function toBoostAmount(uint256 usdAmount) internal view returns (uint256) {
        return usdAmount * 10 ** (boostDecimals - usdDecimals);
    }

    /**
     * @notice Converts a Boost amount to the equivalent USD amount based on token decimals.
     * @param boostAmount The amount in Boost.
     * @return The corresponding amount in USD.
     */
    function toUsdAmount(uint256 boostAmount) internal view returns (uint256) {
        return boostAmount / 10 ** (boostDecimals - usdDecimals);
    }

    /**
     * @notice Retrieves the balance of a specified token held by this contract.
     * @param token The address of the ERC20 token.
     * @return The token balance.
     */
    function balanceOfToken(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Calculates the lower bound for a given price based on the valid range width.
     * @param price The current price.
     * @return The lower bound price.
     */
    function priceLowerBound(uint256 price) internal view returns (uint256) {
        return price - ((price * validRangeWidth) / FACTOR);
    }

    /**
     * @notice Calculates the upper bound for a given price based on the valid range width.
     * @param price The current price.
     * @return The upper bound price.
     */
    function priceUpperBound(uint256 price) internal view returns (uint256) {
        return price + ((price * validRangeWidth) / FACTOR);
    }

    ////////////////////////// VIEW FUNCTIONS //////////////////////////
    /**
     * @notice Retrieves the current price of Boost tokens.
     * @return price The current Boost price.
     * @dev Must be implemented by a derived contract.
     */
    function boostPrice() public view virtual returns (uint256 price);

    // # FIXME: rename to a better name like targetBoostRelativePrice
    /// @inheritdoc IMasterAMO
    function targetPrice() public view override returns (uint256 price) {
        uint256 baseUnit = 10 ** PRICE_DECIMALS;
        if (pairedTokenType == PairedTokenType.STABLE) return baseUnit;
        else if (pairedTokenType == PairedTokenType.SUSDE)
            return IPriceManager(priceManager).sUsdePreviewDeposit(baseUnit) + targetPricePremium;
        else if (pairedTokenType == PairedTokenType.SFRAX)
            return IPriceManager(priceManager).sFraxPreviewDeposit(baseUnit) + targetPricePremium;
        else if (pairedTokenType == PairedTokenType.SDAI)
            return IPriceManager(priceManager).sDaiPreviewDeposit(baseUnit) + targetPricePremium;
        else revert InvalidPairedTokenType();
    }

    function _validateSwap(bool boostForUsd) internal view virtual;
}
