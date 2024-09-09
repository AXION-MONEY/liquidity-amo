// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";
import {ILiquidityAMO} from "./interfaces/ILiquidityAMO.sol";
import {ISolidlyV3Factory} from "./interfaces/ISolidlyV3Factory.sol";
import {ISolidlyV3Pool} from "./interfaces/ISolidlyV3Pool.sol";

/// @title Liquidity AMO for BOOST-USD Solidly pair
/// @notice The LiquidityAMO contract is responsible for maintaining the BOOST-USD peg in Solidly pairs. It achieves
/// this through minting and burning BOOST tokens, as well as adding and removing liquidity from the BOOST-USD pair.
contract LiquidityAMO is ILiquidityAMO, Initializable, AccessControlEnumerableUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== ROLES ========== */
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant AMO_ROLE = keccak256("AMO_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /* ========== VARIABLES ========== */
    address public boost;
    address public usd;
    address public pool;
    uint256 public boostDecimals;
    uint256 public usdDecimals;
    address public boostMinter;
    address public treasuryVault;
    uint256 public boostAmountLimit;
    uint256 public liquidityAmountLimit;
    uint256 public validRangeRatio; // decimals 6
    uint256 public boostMultiplier; // decimals 6
    uint256 public epsilon; // decimals 6
    uint256 public delta; // decimals 6
    int24 tickLower;
    int24 tickUpper;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address pool_,
        address boostMinter_,
        address treasuryVault_
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
            "LiquidityAMO: ZERO_ADDRESS"
        );
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        boost = boost_;
        usd = usd_;
        pool = pool_;
        boostDecimals = IERC20(boost).decimals();
        usdDecimals = IERC20(usd).decimals();
        boostMinter = boostMinter_;
        treasuryVault = treasuryVault_;
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// SETTER_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ILiquidityAMO
    function setVault(
        address treasuryVault_
    ) external onlyRole(SETTER_ROLE) {
        require(
            treasuryVault_ != address(0),
            "LiquidityAMO: ZERO_ADDRESS"
        );
        treasuryVault = treasuryVault_;

        emit SetVault(treasuryVault_);
    }

    /// @inheritdoc ILiquidityAMO
    function setParams(
        uint256 boostAmountLimit_,
        uint256 liquidityAmountLimit_,
        uint256 validRangeRatio_,
        uint256 boostMultiplier_,
        uint256 delta_,
        uint256 epsilon_
    ) external onlyRole(SETTER_ROLE) {
        require(validRangeRatio_ <= 1e6, "LiquidityAMO: INVALID_RATIO_VALUE");
        boostAmountLimit = boostAmountLimit_;
        liquidityAmountLimit = liquidityAmountLimit_;
        validRangeRatio = validRangeRatio_;
        boostMultiplier = boostMultiplier_;
        delta = delta_;
        epsilon = epsilon_;
        emit SetParams(boostAmountLimit_, liquidityAmountLimit_, validRangeRatio_, boostMultiplier_, delta_, epsilon_);
    }

    function setTickBounds(
        int24 tickLower_,
        int24 tickUpper_
    ) external onlyRole(SETTER_ROLE) {
        tickLower = tickLower_;
        tickUpper = tickUpper_;
        emit SetTick(tickLower, tickUpper);
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ILiquidityAMO
    function mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) public onlyRole(AMO_ROLE) whenNotPaused
    returns (uint256 usdAmountOut, uint256 dryPowderAmount) {
        // Ensure the BOOST amount does not exceed the allowed limit
        require(
            boostAmount <= boostAmountLimit,
            "LiquidityAMO: BOOST_AMOUNT_LIMIT_EXCEEDED"
        );
        if (toUsdAmount(boostAmount) > minUsdAmountOut)
            minUsdAmountOut = toUsdAmount(boostAmount);

        // Mint the specified amount of BOOST tokens
        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of BOOST tokens to the pool
        IERC20Upgradeable(boost).approve(pool, boostAmount);

        // Execute the swap
        (int256 amount0, int256 amount1) = ISolidlyV3Pool(pool).swap(
            address(this),
            boost < usd,
            int256(boostAmount),
            0, // sqrtPriceLimitX96
            minUsdAmountOut,
            deadline
        );
        (, int256 usdDelta) = sortAmounts(amount0, amount1);
        usdAmountOut = uint256(- usdDelta);

        dryPowderAmount = usdAmountOut * delta / 1e6;
        // Transfer the dry powder USD to the treasury
        IERC20Upgradeable(usd).safeTransfer(treasuryVault, dryPowderAmount);

        // Emit events for minting BOOST tokens and executing the swap
        emit MintBoost(boostAmount);
        emit Swap(boost, usd, boostAmount, usdAmountOut);
    }

    /// @inheritdoc ILiquidityAMO
    function addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    ) public onlyRole(AMO_ROLE) whenNotPaused
    returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity)  {
        // Mint the specified amount of BOOST tokens
        uint256 boostAmount = toBoostAmount(usdAmount) * boostMultiplier / 1e6;

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
        uint256 validRange = boostSpent * validRangeRatio / 1e6;
        require(
            toBoostAmount(usdSpent) > boostSpent - validRange &&
            toBoostAmount(usdSpent) < boostSpent + validRange,
            "LiquidityAMO: INVALID_RANGE_TO_ADD_LIQUIDITY"
        );

        // Burn excessive boosts
        IBoostStablecoin(boost).burn(boostAmount - boostSpent);

        // Emit event for adding liquidity
        emit AddLiquidity(boostAmount, usdAmount, boostSpent, usdSpent, liquidity);
    }

    /// @inheritdoc ILiquidityAMO
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) whenNotPaused
    returns (uint256 usdAmountOut, uint256 dryPowderAmount, uint256 boostSpent, uint256 usdSpent, uint256 liquidity) {
        (usdAmountOut, dryPowderAmount) = mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);
        uint256 usdBalance = usdAmountOut - dryPowderAmount;
        (boostSpent, usdSpent, liquidity) = addLiquidity(usdBalance, minBoostSpend, minUsdSpend, deadline);
    }

    /// @inheritdoc ILiquidityAMO
    function unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) whenNotPaused
    returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut) {
        (uint256 totalLiquidity, uint128 boostOwed, uint128 usdOwed) = position();
        // Ensure the liquidity amount does not exceed the allowed limit
        require(
            liquidity <= liquidityAmountLimit &&
            liquidity <= totalLiquidity,
            "LiquidityAMO: LIQUIDITY_AMOUNT_LIMIT_EXCEEDED"
        );

        (uint256 amount0Min, uint256 amount1Min) = sortAmounts(minBoostRemove, minUsdRemove);
        (uint256 amount0ToCollect, uint256 amount1ToCollect) = sortAmounts(boostOwed, usdOwed);
        // Remove liquidity and store the amounts of USD and BOOST tokens received
        (uint256 amount0FromBurn, uint256 amount1FromBurn, uint128 amount0Collected, uint128 amount1Collected) =
        ISolidlyV3Pool(pool).burnAndCollect(
            address(this),
            tickLower,
            tickUpper,
            uint128(liquidity),
            amount0Min,
            amount1Min,
            uint128(amount0ToCollect),
            uint128(amount1ToCollect),
            deadline
        );
        (boostRemoved, usdRemoved) = sortAmounts(amount0FromBurn, amount1FromBurn);
        (uint256 boostCollected, uint256 usdCollected) = sortAmounts(amount0Collected, amount1Collected);

        // Ensure the BOOST amount is greater than or equal to the USD amount
        require(
            boostRemoved * epsilon / 1e6 >= toBoostAmount(usdRemoved),
            "LiquidityAMO: REMOVE_LIQUIDITY_WITH_WRONG_RATIO"
        );
        if (toBoostAmount(usdRemoved) > minBoostAmountOut)
            minBoostAmountOut = toBoostAmount(usdRemoved);

        // Approve the transfer of usd tokens to the pool
        IERC20Upgradeable(usd).approve(pool, usdRemoved);

        // Execute the swap and store the amounts of tokens involved
        (int256 amount0, int256 amount1) = ISolidlyV3Pool(pool).swap(
            address(this),
            boost > usd,
            int256(usdRemoved),
            0, // sqrtPriceLimitX96
            minBoostAmountOut,
            deadline
        );
        (int256 boostDelta,) = sortAmounts(amount0, amount1);
        boostAmountOut = uint256(- boostDelta);

        // Burn the BOOST tokens received from burn liquidity, collect owed tokens and swap
        IBoostStablecoin(boost).burn(boostRemoved + boostCollected + boostAmountOut);

        // Emit events for removing liquidity, burning BOOST tokens, and executing the swap
        emit RemoveLiquidity(
            minBoostRemove,
            minUsdRemove,
            boostRemoved,
            usdRemoved,
            liquidity
        );
        emit CollectOwedTokens(boostCollected, usdCollected);
        emit Swap(usd, boost, usdRemoved, boostAmountOut);
        emit BurnBoost(boostRemoved + boostCollected + boostAmountOut);
    }


    ////////////////////////// OPERATOR_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ILiquidityAMO
    function _call(
        address _target,
        bytes calldata _calldata
    ) external payable onlyRole(OPERATOR_ROLE) returns (bool _success, bytes memory _resultdata) {
        return _target.call{value : msg.value}(_calldata);
    }

    ////////////////////////// Internal functions //////////////////////////
    function sortAmounts(uint256 amount0, uint256 amount1) internal view returns (uint256, uint256) {
        if (boost < usd)
            return (amount0, amount1);
        return (amount1, amount0);
    }

    function sortAmounts(int256 amount0, int256 amount1) internal view returns (int256, int256) {
        if (boost < usd)
            return (amount0, amount1);
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
        (uint128 _liquidity,,) = position();
        return usdAmount * _liquidity / IERC20Upgradeable(usd).balanceOf(pool);
    }

    function liquidityForBoost(uint256 boostAmount) public view returns (uint256 liquidityAmount) {
        (uint128 _liquidity,,) = position();
        return boostAmount * _liquidity / IERC20Upgradeable(boost).balanceOf(pool);
    }
}