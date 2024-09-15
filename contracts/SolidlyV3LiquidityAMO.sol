// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./interfaces/v3/ISolidlyV3LiquidityAMO.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";
import {ISolidlyV3Factory} from "./interfaces/v3/ISolidlyV3Factory.sol";
import {ISolidlyV3Pool} from "./interfaces/v3/ISolidlyV3Pool.sol";

/// @title Liquidity AMO for BOOST-USD Solidly pair
/// @notice The SolidlyV3LiquidityAMO contract is responsible for maintaining the BOOST-USD peg in Solidly pairs. It achieves
/// this through minting and burning BOOST tokens, as well as adding and removing liquidity from the BOOST-USD pair.
contract SolidlyV3LiquidityAMO is
    ISolidlyV3LiquidityAMO,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== ROLES ========== */
    bytes32 public constant override SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant override AMO_ROLE = keccak256("AMO_ROLE");
    bytes32 public constant override OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    /* ========== VARIABLES ========== */
    address public override boost;
    address public override usd;
    address public override pool;
    uint256 public override boostDecimals;
    uint256 public override usdDecimals;
    address public override boostMinter;

    address public override treasuryVault;
    uint256 public override boostAmountLimit;
    uint256 public override liquidityAmountLimit;
    uint256 public override validRangeRatio; // decimals 6
    uint256 public override boostMultiplier; // decimals 6
    uint256 public override epsilon; // decimals 6
    uint256 public override delta; // decimals 6
    int24 public override tickLower;
    int24 public override tickUpper;
    uint160 public override targetSqrtPriceX96;

    /* ========== CONSTANTS ========== */
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint256 internal constant Q96 = 2 ** 96;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address pool_,
        address boostMinter_,
        address treasuryVault_,
        uint160 targetSqrtPriceX96_
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        require(
            admin != address(0) &&
                boost_ != address(0) &&
                usd_ != address(0) &&
                pool_ != address(0) &&
                boostMinter_ != address(0) &&
                treasuryVault_ != address(0),
            "SolidlyV3LiquidityAMO: ZERO_ADDRESS"
        );
        require(
            targetSqrtPriceX96_ > MIN_SQRT_RATIO && targetSqrtPriceX96_ < MAX_SQRT_RATIO,
            "SolidlyV3LiquidityAMO: INVALID_RATIO_VALUE"
        );
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        boost = boost_;
        usd = usd_;
        pool = pool_;
        boostDecimals = IERC20Metadata(boost).decimals();
        usdDecimals = IERC20Metadata(usd).decimals();
        boostMinter = boostMinter_;
        treasuryVault = treasuryVault_;
        targetSqrtPriceX96 = targetSqrtPriceX96_;
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
    function setVault(address treasuryVault_) external override onlyRole(SETTER_ROLE) {
        require(treasuryVault_ != address(0), "SolidlyV3LiquidityAMO: ZERO_ADDRESS");
        treasuryVault = treasuryVault_;

        emit SetVault(treasuryVault_);
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function setParams(
        uint256 boostAmountLimit_,
        uint256 liquidityAmountLimit_,
        uint256 validRangeRatio_,
        uint256 boostMultiplier_,
        uint256 delta_,
        uint256 epsilon_
    ) external override onlyRole(SETTER_ROLE) {
        require(validRangeRatio_ <= 1e6, "SolidlyV3LiquidityAMO: INVALID_RATIO_VALUE");
        boostAmountLimit = boostAmountLimit_;
        liquidityAmountLimit = liquidityAmountLimit_;
        validRangeRatio = validRangeRatio_;
        boostMultiplier = boostMultiplier_;
        delta = delta_;
        epsilon = epsilon_;
        emit SetParams(boostAmountLimit_, liquidityAmountLimit_, validRangeRatio_, boostMultiplier_, delta_, epsilon_);
    }

    function setTickBounds(int24 tickLower_, int24 tickUpper_) external override onlyRole(SETTER_ROLE) {
        tickLower = tickLower_;
        tickUpper = tickUpper_;
        emit SetTick(tickLower_, tickUpper_);
    }

    function setTargetSqrtPriceX96(uint160 targetSqrtPriceX96_) external override onlyRole(SETTER_ROLE) {
        require(
            targetSqrtPriceX96_ > MIN_SQRT_RATIO && targetSqrtPriceX96_ < MAX_SQRT_RATIO,
            "SolidlyV3LiquidityAMO: INVALID_RATIO_VALUE"
        );
        targetSqrtPriceX96 = targetSqrtPriceX96_;
        emit SetTargetSqrtPriceX96(targetSqrtPriceX96_);
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    )
        public
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 dryPowderAmount)
    {
        // Ensure the BOOST amount does not exceed the allowed limit
        require(boostAmount <= boostAmountLimit, "SolidlyV3LiquidityAMO: BOOST_AMOUNT_LIMIT_EXCEEDED");

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
        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0, amount1);
        boostAmountIn = uint256(boostDelta);
        usdAmountOut = uint256(-usdDelta);
        require(toBoostAmount(usdAmountOut) > boostAmountIn, "SolidlyV3LiquidityAMO: INSUFFICIENT_OUTPUT_AMOUNT");

        dryPowderAmount = (usdAmountOut * delta) / 1e6;
        // Transfer the dry powder USD to the treasury
        IERC20Upgradeable(usd).safeTransfer(treasuryVault, dryPowderAmount);

        // Burn excessive boosts
        IBoostStablecoin(boost).burn(boostAmount - boostAmountIn);

        // Emit events for minting BOOST tokens and executing the swap
        emit MintBoost(boostAmountIn);
        emit Swap(boost, usd, boostAmountIn, usdAmountOut);
    }

    /// @inheritdoc ISolidlyV3LiquidityAMOActions
    function addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        public
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        // Mint the specified amount of BOOST tokens
        uint256 boostAmount = (toBoostAmount(usdAmount) * boostMultiplier) / 1e6;

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
        (boostSpent, usdSpent) = sortAmounts(amount0, amount1);

        // Calculate the valid range for USD spent based on the BOOST spent and the validRangeRatio
        uint256 validRange = (boostSpent * validRangeRatio) / 1e6;
        require(
            toBoostAmount(usdSpent) > boostSpent - validRange && toBoostAmount(usdSpent) < boostSpent + validRange,
            "SolidlyV3LiquidityAMO: INVALID_RANGE_TO_ADD_LIQUIDITY"
        );

        // Burn excessive boosts
        IBoostStablecoin(boost).burn(boostAmount - boostSpent);

        // Emit event for adding liquidity
        emit AddLiquidity(boostAmount, usdAmount, boostSpent, usdSpent, liquidity);
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
        returns (
            uint256 boostAmountIn,
            uint256 usdAmountOut,
            uint256 dryPowderAmount,
            uint256 boostSpent,
            uint256 usdSpent,
            uint256 liquidity
        )
    {
        (boostAmountIn, usdAmountOut, dryPowderAmount) = mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);

        uint256 price = boostPrice();
        if (price > 1e6 - validRangeRatio && price < 1e6 + validRangeRatio) {
            uint256 usdBalance = IERC20Upgradeable(usd).balanceOf(address(this));
            (boostSpent, usdSpent, liquidity) = addLiquidity(usdBalance, minBoostSpend, minUsdSpend, deadline);
        }
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
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut)
    {
        (uint256 totalLiquidity, , ) = position();
        // Ensure the liquidity amount does not exceed the allowed limit
        require(
            liquidity <= liquidityAmountLimit && liquidity <= totalLiquidity,
            "SolidlyV3LiquidityAMO: LIQUIDITY_AMOUNT_LIMIT_EXCEEDED"
        );

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
        require(
            (boostRemoved * epsilon) / 1e6 >= toBoostAmount(usdRemoved),
            "SolidlyV3LiquidityAMO: REMOVE_LIQUIDITY_WITH_WRONG_RATIO"
        );

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
        (int256 boostDelta, int256 usdDelta) = sortAmounts(amount0, amount1);
        usdAmountIn = uint256(usdDelta);
        boostAmountOut = uint256(-boostDelta);
        require(toUsdAmount(boostAmountOut) > usdAmountIn, "SolidlyV3LiquidityAMO: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            usdRemoved - usdAmountIn < 100 * 10 ** usdDecimals,
            "SolidlyV3LiquidityAMO: REMOVED_TOO_MUCH_LIQUIDITY"
        );

        // Burn the BOOST tokens received from burn liquidity, collect owed tokens and swap
        IBoostStablecoin(boost).burn(boostCollected + boostAmountOut);

        // Emit events for removing liquidity, burning BOOST tokens, and executing the swap
        emit RemoveLiquidity(minBoostRemove, minUsdRemove, boostRemoved, usdRemoved, liquidity);
        emit CollectOwedTokens(boostCollected - boostRemoved, usdCollected - usdRemoved);
        emit Swap(usd, boost, usdAmountIn, boostAmountOut);
        emit BurnBoost(boostCollected + boostAmountOut);
    }

    ////////////////////////// OPERATOR_ROLE ACTIONS //////////////////////////
    function _call(
        address _target,
        bytes calldata _calldata
    ) external payable onlyRole(OPERATOR_ROLE) returns (bool _success, bytes memory _resultdata) {
        return _target.call{value: msg.value}(_calldata);
    }

    function _call(
        address _target,
        bytes calldata _calldata,
        bool _requireSuccess
    ) external payable onlyRole(OPERATOR_ROLE) returns (bool _success, bytes memory _resultdata) {
        (_success, _resultdata) = _target.call{value: msg.value}(_calldata);
        if (_requireSuccess) require(_success, string(_resultdata));
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
            price = (10 ** (boostDecimals - usdDecimals + 6) * sqrtPriceX96 ** 2) / Q96 ** 2;
        } else {
            price = sqrtPriceX96 ** 2 / Q96 ** 2 / 10 ** (boostDecimals - usdDecimals - 6);
        }
    }
}
