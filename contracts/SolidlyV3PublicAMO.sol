// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ISolidlyV3LiquidityAMO} from "./interfaces/v3/ISolidlyV3LiquidityAMO.sol";
import {ISolidlyV3PublicAMO} from "./interfaces/v3/ISolidlyV3PublicAMO.sol";
import {ISolidlyV3Pool} from "./interfaces/v3/ISolidlyV3Pool.sol";

/// @title A public wrapper for BOOST-USD LiquidityAMO
/// @notice The PublicAMO contract is responsible for maintaining the BOOST-USD peg in Solidly pairs.
/// It achieves this through minting and burning BOOST tokens, as well as adding and removing liquidity from the BOOST-USD pair.
/// @dev This contract implements the ISolidlyV3PublicAMO interface and inherits from Initializable, AccessControlEnumerableUpgradeable, and PausableUpgradeable.
contract SolidlyV3PublicAMO is
    ISolidlyV3PublicAMO,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    ////////////////////////// ROLES //////////////////////////
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    ////////////////////////// VARIABLES //////////////////////////
    ISolidlyV3LiquidityAMO public amo;
    uint256 public boostLowerPriceSell; // Decimals: 6
    uint256 public boostUpperPriceBuy; // Decimals: 6
    uint256 public boostToMintLimit;
    uint256 public liquidityToUnfarmLimit;
    uint256 public cooldownPeriod;
    mapping(address => uint256) public lastTxTimestamp;

    ////////////////////////// CONSTANTS //////////////////////////
    uint8 private constant DECIMALS = 6;

    ////////////////////////// ERRORS //////////////////////////
    error PriceNotInRange(uint256 price);
    error InvalidBoostAmount(uint256 amount);
    error InvalidLiquidityAmount(uint256 amount);
    error ZeroAddress();
    error InvalidFactorValue();
    error CooldownNotFinished();

    ////////////////////////// INITIALIZER //////////////////////////
    /// @inheritdoc ISolidlyV3PublicAMO
    function initialize(address admin_, address amoAddress_) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        if (admin_ == address(0) || amoAddress_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        amo = ISolidlyV3LiquidityAMO(amoAddress_);
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////

    /// @inheritdoc ISolidlyV3PublicAMO
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc ISolidlyV3PublicAMO
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// PUBLIC FUNCTIONS //////////////////////////
    /// @inheritdoc ISolidlyV3PublicAMO
    function mintSellFarm()
        external
        whenNotPaused
        returns (
            uint256 boostAmountIn,
            uint256 usdAmountOut,
            uint256 dryPowderAmount,
            uint256 boostSpent,
            uint256 usdSpent,
            uint256 liquidity,
            uint256 newBoostPrice
        )
    {
        // Checks cooldown time
        if (lastTxTimestamp[tx.origin] + cooldownPeriod > block.timestamp) revert CooldownNotFinished();
        lastTxTimestamp[tx.origin] = block.timestamp;

        address pool = amo.pool();
        uint160 targetSqrtPriceX96 = amo.targetSqrtPriceX96();
        uint256 boostAmountLimit = amo.boostAmountLimit();
        address boost = amo.boost();
        address usd = amo.usd();
        bool zeroForOne = boost < usd;
        (int256 amount0, int256 amount1, , , ) = ISolidlyV3Pool(pool).quoteSwap(
            zeroForOne,
            int256(boostAmountLimit),
            targetSqrtPriceX96
        );
        uint256 boostAmount;
        if (zeroForOne) boostAmount = uint256(amount0);
        else boostAmount = uint256(amount1);

        // Set a high limit on boost amount to be minted, sold and farmed
        if (boostAmount > boostToMintLimit) revert InvalidBoostAmount(boostAmount);

        (boostAmountIn, usdAmountOut, dryPowderAmount, boostSpent, usdSpent, liquidity) = amo.mintSellFarm(
            boostAmount,
            1, // minUsdAmountOut
            1, // minBoostSpend
            1, // minUsdSpend
            block.timestamp + 1 // deadline
        );

        newBoostPrice = amo.boostPrice();

        // Checks if the actual average price of boost when selling is greater than the boostLowerPriceSell
        if (newBoostPrice < boostLowerPriceSell) revert PriceNotInRange(newBoostPrice);

        emit MintSellFarmExecuted(boostAmountIn, usdAmountOut, liquidity);
    }

    /// @inheritdoc ISolidlyV3PublicAMO
    function unfarmBuyBurn(
        uint24 liquidityFactor
    )
        external
        whenNotPaused
        returns (
            uint256 boostRemoved,
            uint256 usdRemoved,
            uint256 usdAmountIn,
            uint256 boostAmountOut,
            uint256 newBoostPrice
        )
    {
        // Checks cooldown time
        if (lastTxTimestamp[tx.origin] + cooldownPeriod > block.timestamp) revert CooldownNotFinished();
        lastTxTimestamp[tx.origin] = block.timestamp;

        // Check liquidity factor
        if (liquidityFactor > 10 ** DECIMALS) revert InvalidFactorValue();

        address pool = amo.pool();
        address boost = amo.boost();
        address usd = amo.usd();
        uint128 liquidity = ISolidlyV3Pool(pool).liquidity();
        uint256 boostBalance = IERC20(boost).balanceOf(pool);
        uint256 usdBalance = IERC20(usd).balanceOf(pool);
        uint8 boostDecimals = IERC20Metadata(boost).decimals();
        uint8 usdDecimals = IERC20Metadata(usd).decimals();
        usdBalance *= 10 ** (boostDecimals - usdDecimals);
        if (boostBalance <= usdBalance) revert PriceNotInRange(amo.boostPrice());

        uint256 liquidityToUnfarm = (liquidity * (boostBalance - usdBalance)) / (boostBalance + usdBalance);
        liquidityToUnfarm = (liquidityToUnfarm * liquidityFactor) / 10 ** DECIMALS;

        // Set a high limit on liquidity amount to be unfarmed, bought and burned
        if (liquidityToUnfarm > liquidityToUnfarmLimit) revert InvalidLiquidityAmount(liquidityToUnfarm);

        (boostRemoved, usdRemoved, usdAmountIn, boostAmountOut) = amo.unfarmBuyBurn(
            liquidityToUnfarm,
            1, // minBoostRemove
            1, // minUsdRemove
            1, // minBoostAmountOut
            block.timestamp + 1 // deadline
        );

        newBoostPrice = amo.boostPrice();

        // Checks if the actual average price of boost when buying is less than the boostUpperPriceBuy
        if (newBoostPrice > boostUpperPriceBuy) revert PriceNotInRange(newBoostPrice);

        emit UnfarmBuyBurnExecuted(liquidityToUnfarm, boostRemoved, usdRemoved);
    }

    ////////////////////////// SETTER FUNCTIONS //////////////////////////
    /// @inheritdoc ISolidlyV3PublicAMO
    function setLimits(uint256 boostLimitToMint_, uint256 liquidityToUnfarmLimit_) external onlyRole(SETTER_ROLE) {
        boostToMintLimit = boostLimitToMint_;
        liquidityToUnfarmLimit = liquidityToUnfarmLimit_;
        emit LimitsSet(boostLimitToMint_, liquidityToUnfarmLimit_);
    }

    /// @inheritdoc ISolidlyV3PublicAMO
    function setBuyAndSellBound(
        uint256 boostUpperPriceBuy_,
        uint256 boostLowerPriceSell_
    ) external onlyRole(SETTER_ROLE) {
        boostUpperPriceBuy = boostUpperPriceBuy_;
        boostLowerPriceSell = boostLowerPriceSell_;
        emit BuyAndSellBoundSet(boostUpperPriceBuy_, boostLowerPriceSell_);
    }

    /// @inheritdoc ISolidlyV3PublicAMO
    function setAmo(address amoAddress_) external onlyRole(SETTER_ROLE) {
        if (amoAddress_ == address(0)) revert ZeroAddress();
        amo = ISolidlyV3LiquidityAMO(amoAddress_);
        emit AMOSet(amoAddress_);
    }

    /// @inheritdoc ISolidlyV3PublicAMO
    function setCooldownPeriod(uint256 cooldownPeriod_) external onlyRole(SETTER_ROLE) {
        cooldownPeriod = cooldownPeriod_;
        emit CooldownPeriodSet(cooldownPeriod_);
    }
}
