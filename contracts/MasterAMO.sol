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

    // -------------------------------------------------------------
    //                             ROLES
    // -------------------------------------------------------------
    /// @inheritdoc IMasterAMO
    bytes32 public constant override SETTER_ROLE = keccak256("SETTER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    // -------------------------------------------------------------
    //                        STATE VARIABLES
    // -------------------------------------------------------------

    ////// IMMUTABLE //////
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
    /// @inheritdoc IMasterAMO
    address public priceManager;
    /// @inheritdoc IMasterAMO
    PairedTokenType public pairedTokenType;

    ////// MUTABLE //////
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
    /// @inheritdoc IMasterAMO
    uint256 public override targetPricePremium;

    // -------------------------------------------------------------
    //                      INTERNAL CONSTANTS
    // -------------------------------------------------------------
    // @notice BOOST price decimals
    uint8 internal constant PRICE_DECIMALS = 6;
    // @notice Decimals for parameter calculations.
    uint8 internal constant PARAMS_DECIMALS = 6;
    // @notice Scaling factor.
    uint256 internal constant FACTOR = 10 ** PARAMS_DECIMALS;
    // @notice Indicates a Boost → USD swap.
    bool internal constant SELL_BOOST = true;
    // @notice Indicates a USD → Boost swap.
    bool internal constant BUY_BOOST = false;

    // -------------------------------------------------------------
    //                           MODIFIERS
    // -------------------------------------------------------------
    /**
     * @dev Modifier to validate swap parameters.
     * @param boostForUsd A boolean indicating the swap direction: true for Boost → USD, false for USD → Boost.
     */
    modifier validateSwap(bool boostForUsd) {
        _validateSwap(boostForUsd);
        _;
    }

    // -------------------------------------------------------------
    //                        INITIALIZATION
    // -------------------------------------------------------------
    /**
     * @notice Initializes the MasterAMO contract.
     * @param admin Address to be granted the DEFAULT_ADMIN_ROLE.
     * @param boost_ Address of the Boost stablecoin.
     * @param usd_ Address of the USD stablecoin.
     * @param pool_ Address of the liquidity pool for the Boost-USD pair.
     * @param boostMinter_ Address of the Boost minter contract.
     * @param priceManager_ Address of the price manager contract.
     * @param pairedTokenType_ The type of token paired with Boost.
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
        targetPricePremium = 0; // Default value.
    }

    // -------------------------------------------------------------
    //                        SETTER ACTIONS
    // -------------------------------------------------------------
    /**
     * @notice Sets the premium offset used in target price calculations.
     * @param _targetPricePremium The new premium offset.
     */
    function setTargetPricePremium(uint256 _targetPricePremium) external onlyRole(SETTER_ROLE) {
        targetPricePremium = _targetPricePremium;
        emit SetTargetPricePremium(targetPricePremium);
    }

    // -------------------------------------------------------------
    //                        PAUSE ACTIONS
    // -------------------------------------------------------------
    /// @inheritdoc IMasterAMO
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IMasterAMO
    function unpause() external override onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    // -------------------------------------------------------------
    //                INTERNAL HELPER VIEW FUNCTIONS
    // -------------------------------------------------------------
    /**
     * @notice Sorts two token amounts based on token addresses.
     * @param amount0 The first token amount.
     * @param amount1 The second token amount.
     * @return (uint256, uint256) The sorted token amounts.
     */
    function sortAmounts(uint256 amount0, uint256 amount1) internal view returns (uint256, uint256) {
        if (boost < usd) return (amount0, amount1);
        return (amount1, amount0);
    }

    /**
     * @notice Sorts two signed token amounts based on token addresses.
     * @param amount0 The first token amount.
     * @param amount1 The second token amount.
     * @return (int256, int256) The sorted token amounts.
     */
    function sortAmounts(int256 amount0, int256 amount1) internal view returns (int256, int256) {
        if (boost < usd) return (amount0, amount1);
        return (amount1, amount0);
    }

    /**
     * @notice Converts a USD amount to the equivalent BOOST amount.
     * @param usdAmount Amount in USD.
     * @return The corresponding BOOST amount.
     */
    function toBoostAmount(uint256 usdAmount) internal view returns (uint256) {
        return usdAmount * 10 ** (boostDecimals - usdDecimals);
    }

    /**
     * @notice Converts a BOOST amount to the equivalent USD amount.
     * @param boostAmount Amount in BOOST.
     * @return The corresponding USD amount.
     */
    function toUsdAmount(uint256 boostAmount) internal view returns (uint256) {
        return boostAmount / 10 ** (boostDecimals - usdDecimals);
    }

    /**
     * @notice Retrieves the balance of a specified token held by this contract.
     * @param token ERC20 token address.
     * @return The token balance.
     */
    function balanceOfToken(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Calculates the lower price bound based on the valid range.
     * @param price Current price.
     * @return The lower bound price.
     */
    function priceLowerBound(uint256 price) internal view returns (uint256) {
        return price - ((price * validRangeWidth) / FACTOR);
    }

    /**
     * @notice Calculates the upper price bound based on the valid range.
     * @param price Current price.
     * @return The upper bound price.
     */
    function priceUpperBound(uint256 price) internal view returns (uint256) {
        return price + ((price * validRangeWidth) / FACTOR);
    }

    /**
     * @notice Internal function to validate swap parameters.
     * @param boostForUsd Swap direction: true for Boost → USD, false for USD → Boost.
     */
    function _validateSwap(bool boostForUsd) internal view virtual;

    // -------------------------------------------------------------
    //                   INTERNAL FUNCTIONS
    // -------------------------------------------------------------

    ////// MINT-SELL-FARM FUNCTIONS //////

    /**
     * @notice Internal function to mint BOOST and sell it for USD.
     * @param boostAmount The amount of BOOST to mint.
     * @return boostAmountIn BOOST tokens sent to the pool.
     * @return usdAmountOut USD tokens received.
     * @dev Must be implemented by a derived contract.
     */
    function _mintAndSellBoost(
        uint256 boostAmount
    ) internal virtual returns (uint256 boostAmountIn, uint256 usdAmountOut);

    /**
     * @notice Internal function to add liquidity to the pool.
     * @param usdAmount The USD amount to add.
     * @param minBoostSpend Minimum BOOST tokens to spend.
     * @param minUsdSpend Minimum USD tokens to spend.
     * @return boostSpent BOOST tokens spent.
     * @return usdSpent USD tokens spent.
     * @return liquidity Liquidity tokens received.
     * @dev Must be implemented by a derived contract.
     */
    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    ) internal virtual returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity);

    /**
     * @notice Internal function that mints, sells BOOST, and adds liquidity.
     * @param boostAmount The BOOST amount to mint.
     * @param minBoostSpend Minimum BOOST tokens to spend.
     * @param minUsdSpend Minimum USD tokens to spend.
     * @return boostAmountIn BOOST tokens used in the swap.
     * @return usdAmountOut USD tokens received from the swap.
     * @return boostSpent BOOST tokens spent in liquidity addition.
     * @return usdSpent USD tokens spent in liquidity addition.
     * @return liquidity Liquidity tokens received.
     * @dev Has been Used for AMO-ROLE functions
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
    /**
     * @notice Internal function to perform mint, sell and liquidity addition when BOOST is over peg.
     * @return liquidity Liquidity tokens received.
     * @return newBoostPrice The new average BOOST price after the operation.
     * @dev Must be implemented by a derived contract.
     * @dev Has been Used for public functions
     */
    function _mintSellFarm() internal virtual returns (uint256 liquidity, uint256 newBoostPrice);

    ////// UNFARM-BUY-BURN FUNCTIONS //////

    /**
     * @notice Internal function to remove liquidity, buy BOOST, and burn it.
     * @param liquidity The liquidity tokens to remove.
     * @param minBoostRemove Minimum BOOST tokens to remove.
     * @param minUsdRemove Minimum USD tokens to remove.
     * @return boostRemoved BOOST tokens removed.
     * @return usdRemoved USD tokens removed.
     * @return usdAmountIn USD tokens used to buy BOOST.
     * @return boostAmountOut BOOST tokens obtained.
     * @dev Must be implemented by a derived contract.
     * @dev Has been Used for AMO-ROLE functions
     */
    function _unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove
    ) internal virtual returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut);

    /**
     * @notice Internal function to perform un-farming, buying, and burning when BOOST is under peg.
     * @return liquidity Liquidity tokens affected.
     * @return newBoostPrice The new average BOOST price after the operation.
     * @dev Must be implemented by a derived contract.
     * @dev Has been Used for public functions
     */
    function _unfarmBuyBurn() internal virtual returns (uint256 liquidity, uint256 newBoostPrice);

    // -------------------------------------------------------------
    //                      EXTERNAL FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IMasterAMO
    function mintSellFarm()
        external
        override
        whenNotPaused
        nonReentrant
        validateSwap(SELL_BOOST)
        returns (uint256 liquidity, uint256 newBoostPrice)
    {
        (liquidity, newBoostPrice) = _mintSellFarm();
        uint256 tp = targetPrice();
        if (newBoostPrice < (tp * boostLowerPriceSell) / FACTOR) revert PriceNotInRange(newBoostPrice);
        emit PublicMintSellFarmExecuted(liquidity, newBoostPrice);
    }

    /// @inheritdoc IMasterAMO
    function unfarmBuyBurn()
        external
        override
        whenNotPaused
        nonReentrant
        validateSwap(BUY_BOOST)
        returns (uint256 liquidity, uint256 newBoostPrice)
    {
        (liquidity, newBoostPrice) = _unfarmBuyBurn();
        uint256 tp = targetPrice();
        if (newBoostPrice > (tp * boostUpperPriceBuy) / FACTOR) revert PriceNotInRange(newBoostPrice);
        emit PublicUnfarmBuyBurnExecuted(liquidity, newBoostPrice);
    }

    ////// WITHDRAWAL FUNCTIONS //////

    /// @inheritdoc IMasterAMO
    function withdrawERC20(
        address token,
        uint256 amount,
        address recipient
    ) external override onlyRole(WITHDRAWER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(recipient, amount);
    }

    // -------------------------------------------------------------
    //                        VIEW FUNCTIONS
    // -------------------------------------------------------------
    /// @inheritdoc IMasterAMO
    function boostPrice() public view virtual override returns (uint256 price);

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
}
