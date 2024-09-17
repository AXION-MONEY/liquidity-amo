// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ISolidlyV2LiquidityAMO} from "./interfaces/v2/ISolidlyV2LiquidityAMO.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";
import {IGauge} from "./interfaces/v2/IGauge.sol";
import {ISolidlyRouter} from "./interfaces/v2/ISolidlyRouter.sol";
import {IPair} from "./interfaces/v2/IPair.sol";

/// @title Liquidity AMO for BOOST-USD Solidly pair
/// @notice The LiquidityAMO contract is responsible for maintaining the BOOST-USD peg in Solidly pairs. It achieves this through minting and burning BOOST tokens, as well as adding and removing liquidity from the BOOST-USD pair.
contract SolidlyV2LiquidityAMO is
    ISolidlyV2LiquidityAMO,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== ERRORS ========== */
    error ZeroAddress();
    error InvalidRatioValue();
    error BoostAmountLimitExceeded(uint256 amount, uint256 limit);
    error LpAmountLimitExceeded(uint256 amount, uint256 limit);
    error InsufficientOutputAmount(uint256 outputAmount, uint256 minRequired);
    error InvalidRatioToAddLiquidity();
    error InvalidRatioToRemoveLiquidity();
    error TokenNotWhitelisted(address token);
    error UsdAmountOutMismatch(uint256 routerOutput, uint256 balanceChange);
    error LpAmountOutMismatch(uint256 routerOutput, uint256 balanceChange);

    /* ========== ROLES ========== */
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant AMO_ROLE = keccak256("AMO_ROLE");
    bytes32 public constant REWARD_COLLECTOR_ROLE = keccak256("REWARD_COLLECTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /* ========== VARIABLES ========== */
    address public boost;
    address public usd;
    address public pool;
    uint256 public boostDecimals;
    uint256 public usdDecimals;
    address public boostMinter;
    address public router;
    address public gauge;

    address public rewardVault;
    address public treasuryVault;
    uint256 public boostAmountLimit;
    uint256 public lpAmountLimit;
    uint256 public boostMultiplier; // decimals 6
    uint24 public validRangeRatio; // decimals 6
    uint24 public validRemovingRatio; // decimals 6
    uint24 public dryPowderRatio; // decimals 6
    mapping(address => bool) public whitelistedRewardTokens;

    /* ========== CONSTANTS ========== */
    uint8 internal constant PRICE_DECIMALS = 6;
    uint8 internal constant PARAMS_DECIMALS = 6;
    uint256 internal constant FACTOR = 10 ** PARAMS_DECIMALS;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address boostMinter_,
        address router_,
        address gauge_,
        address rewardVault_,
        address treasuryVault_
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        if (
            admin == address(0) ||
            boost_ == address(0) ||
            usd_ == address(0) ||
            boostMinter_ == address(0) ||
            router_ == address(0) ||
            gauge_ == address(0) ||
            rewardVault_ == address(0) ||
            treasuryVault_ == address(0)
        ) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        boost = boost_;
        usd = usd_;
        pool = ISolidlyRouter(router).pairFor(usd, boost, true);
        boostDecimals = IERC20Metadata(boost).decimals();
        usdDecimals = IERC20Metadata(usd).decimals();
        boostMinter = boostMinter_;
        router = router_;
        gauge = gauge_;
        rewardVault = rewardVault_;
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
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setVaults(address rewardVault_, address treasuryVault_) external onlyRole(SETTER_ROLE) {
        if (rewardVault_ == address(0) || treasuryVault_ == address(0)) revert ZeroAddress();
        rewardVault = rewardVault_;
        treasuryVault = treasuryVault_;
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setParams(
        uint256 boostAmountLimit_,
        uint256 lpAmountLimit_,
        uint256 boostMultiplier_,
        uint24 validRangeRatio_,
        uint24 validRemovingRatio_,
        uint24 dryPowderRatio_
    ) external onlyRole(SETTER_ROLE) {
        if (validRangeRatio_ > FACTOR || validRemovingRatio_ > FACTOR || dryPowderRatio_ > FACTOR)
            revert InvalidRatioValue();
        boostAmountLimit = boostAmountLimit_;
        lpAmountLimit = lpAmountLimit_;
        boostMultiplier = boostMultiplier_;
        validRangeRatio = validRangeRatio_;
        validRemovingRatio = validRemovingRatio_;
        dryPowderRatio = dryPowderRatio_;
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setRewardTokens(address[] memory tokens, bool isWhitelisted) external onlyRole(SETTER_ROLE) {
        for (uint i = 0; i < tokens.length; i++) {
            whitelistedRewardTokens[tokens[i]] = isWhitelisted;
        }
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) public onlyRole(AMO_ROLE) whenNotPaused returns (uint256 usdAmountOut, uint256 dryPowderAmount) {
        // Ensure the BOOST amount does not exceed the allowed limit
        if (boostAmount > boostAmountLimit) revert BoostAmountLimitExceeded(boostAmount, boostAmountLimit);

        // Mint the specified amount of BOOST tokens
        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of BOOST tokens to the router
        IERC20Upgradeable(boost).approve(router, boostAmount);

        // Define the route to swap BOOST tokens for USD tokens
        ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](1);
        routes[0] = ISolidlyRouter.route(boost, usd, true);

        if (minUsdAmountOut < toUsdAmount(boostAmount)) minUsdAmountOut = toUsdAmount(boostAmount);

        uint256 usdBalanceBefore = balanceOfToken(usd);
        // Execute the swap and store the amounts of tokens involved
        uint256[] memory amounts = ISolidlyRouter(router).swapExactTokensForTokens(
            boostAmount,
            minUsdAmountOut,
            routes,
            address(this),
            deadline
        );
        uint256 usdBalanceAfter = balanceOfToken(usd);
        usdAmountOut = amounts[1];

        if (usdAmountOut != usdBalanceAfter - usdBalanceBefore)
            revert UsdAmountOutMismatch(usdAmountOut, usdBalanceAfter - usdBalanceBefore);

        if (usdAmountOut < minUsdAmountOut) revert InsufficientOutputAmount(usdAmountOut, minUsdAmountOut);

        dryPowderAmount = (usdAmountOut * dryPowderRatio) / FACTOR;
        // Transfer the dry powder USD to the treasury
        IERC20Upgradeable(usd).safeTransfer(treasuryVault, dryPowderAmount);

        // Emit events for minting BOOST tokens and executing the swap
        emit MintBoost(boostAmount);
        emit Swap(boost, usd, boostAmount, usdAmountOut);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function addLiquidityAndDeposit(
        uint256 tokenId,
        bool useTokenId,
        uint256 usdAmount,
        uint256 minUsdSpend,
        uint256 minLpAmount,
        uint256 deadline
    ) public onlyRole(AMO_ROLE) whenNotPaused returns (uint256 boostSpent, uint256 usdSpent, uint256 lpAmount) {
        // Mint the specified amount of BOOST tokens
        uint256 boostAmount = (toBoostAmount(usdAmount) * boostMultiplier) / FACTOR;

        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of BOOST and USD tokens to the router
        IERC20Upgradeable(boost).approve(router, boostAmount);
        IERC20Upgradeable(usd).approve(router, usdAmount);

        uint256 lpBalanceBefore = balanceOfToken(pool);
        // Add liquidity to the BOOST-USD pool
        (boostSpent, usdSpent, lpAmount) = ISolidlyRouter(router).addLiquidity(
            boost,
            usd,
            true,
            boostAmount,
            usdAmount,
            toBoostAmount(minUsdSpend),
            minUsdSpend,
            address(this),
            deadline
        );
        uint256 lpBalanceAfter = balanceOfToken(pool);

        if (lpAmount != lpBalanceAfter - lpBalanceBefore)
            revert LpAmountOutMismatch(lpAmount, lpBalanceAfter - lpBalanceBefore);

        // Ensure the liquidity tokens minted are greater than or equal to the minimum required
        if (lpAmount < minLpAmount) revert InsufficientOutputAmount(lpAmount, minLpAmount);

        // Calculate the valid range for USD spent based on the BOOST spent and the validRangeRatio
        uint256 validRange = (boostSpent * validRangeRatio) / FACTOR;
        if (toBoostAmount(usdSpent) < boostSpent - validRange || toBoostAmount(usdSpent) > boostSpent + validRange)
            revert InvalidRatioToAddLiquidity();

        // Approve the transfer of liquidity tokens to the gauge and deposit them
        IERC20Upgradeable(pool).approve(gauge, lpAmount);
        if (useTokenId) {
            IGauge(gauge).deposit(lpAmount, tokenId);
        } else {
            IGauge(gauge).deposit(lpAmount);
        }

        // Burn excessive boosts
        if (boostAmount > boostSpent) IBoostStablecoin(boost).burn(boostAmount - boostSpent);

        // Emit events for adding liquidity and depositing liquidity tokens
        emit AddLiquidity(usdAmount, boostAmount, usdSpent, boostSpent, lpAmount);
        emit DepositLP(lpAmount, tokenId);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 tokenId,
        bool useTokenId,
        uint256 minUsdSpend,
        uint256 minLpAmount,
        uint256 deadline
    )
        external
        onlyRole(AMO_ROLE)
        whenNotPaused
        returns (uint256 usdAmountOut, uint256 dryPowderAmount, uint256 boostSpent, uint256 usdSpent, uint256 lpAmount)
    {
        (usdAmountOut, dryPowderAmount) = mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);
        uint256 price = boostPrice();
        if (price > FACTOR - validRangeRatio && price < FACTOR + validRangeRatio) {
            uint256 usdBalance = balanceOfToken(usd);
            (boostSpent, usdSpent, lpAmount) = addLiquidityAndDeposit(
                tokenId,
                useTokenId,
                usdBalance,
                minUsdSpend,
                minLpAmount,
                deadline
            );
        }
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function unfarmBuyBurn(
        uint256 lpAmount,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    )
        external
        onlyRole(AMO_ROLE)
        whenNotPaused
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut)
    {
        // Ensure the LP amount does not exceed the allowed limit
        uint256 totalLp = totalLP();
        if (lpAmount > lpAmountLimit) revert LpAmountLimitExceeded(lpAmount, lpAmountLimit);
        if (lpAmount > totalLp) revert LpAmountLimitExceeded(lpAmount, totalLp);
        // Withdraw the specified amount of liquidity tokens from the gauge
        IGauge(gauge).withdraw(lpAmount);

        // Approve the transfer of liquidity tokens to the router for removal
        IERC20Upgradeable(pool).approve(router, lpAmount);

        // Remove liquidity and store the amounts of USD and BOOST tokens received
        (boostRemoved, usdRemoved) = ISolidlyRouter(router).removeLiquidity(
            boost,
            usd,
            true,
            lpAmount,
            minBoostRemove,
            minUsdRemove,
            address(this),
            deadline
        );

        // Ensure the BOOST amount is greater than or equal to the USD amount
        if ((boostRemoved * validRemovingRatio) / FACTOR < toBoostAmount(usdRemoved))
            revert InvalidRatioToRemoveLiquidity();

        // Define the route to swap USD tokens for BOOST tokens
        ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](1);
        routes[0] = ISolidlyRouter.route(usd, boost, true);

        // Approve the transfer of usd tokens to the router
        IERC20Upgradeable(usd).approve(router, usdRemoved);

        if (minBoostAmountOut < toBoostAmount(usdRemoved)) minBoostAmountOut = toBoostAmount(usdRemoved);

        // Execute the swap and store the amounts of tokens involved
        uint256[] memory amounts = ISolidlyRouter(router).swapExactTokensForTokens(
            usdRemoved,
            minBoostAmountOut,
            routes,
            address(this),
            deadline
        );

        // Burn the BOOST tokens received from the liquidity
        // Burn the BOOST tokens received from the swap
        boostAmountOut = amounts[1];
        IBoostStablecoin(boost).burn(boostRemoved + boostAmountOut);

        // Emit events for withdrawing liquidity tokens, removing liquidity, burning BOOST tokens, and executing the swap
        emit WithdrawLP(lpAmount);
        emit RemoveLiquidity(minUsdRemove, minBoostRemove, usdRemoved, boostRemoved, lpAmount);
        emit Swap(usd, boost, usdRemoved, boostAmountOut);
        emit BurnBoost(boostRemoved + boostAmountOut);
    }

    ////////////////////////// REWARD_COLLECTOR_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function getReward(
        address[] memory tokens,
        bool passTokens
    ) external onlyRole(REWARD_COLLECTOR_ROLE) whenNotPaused {
        _getReward(tokens, passTokens);
    }

    ////////////////////////// Withdrawal functions //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function withdrawERC20(address token, uint256 amount, address recipient) external onlyRole(WITHDRAWER_ROLE) {
        IERC20Upgradeable(token).safeTransfer(recipient, amount);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function withdrawERC721(address token, uint256 tokenId, address recipient) external onlyRole(WITHDRAWER_ROLE) {
        IERC721Upgradeable(token).safeTransferFrom(address(this), recipient, tokenId);
    }

    ////////////////////////// Internal functions //////////////////////////
    function _getReward(address[] memory tokens, bool passTokens) internal {
        uint256[] memory rewardsAmounts = new uint256[](tokens.length);
        // Collect the rewards
        if (passTokens) {
            IGauge(gauge).getReward(address(this), tokens);
        } else {
            IGauge(gauge).getReward();
        }
        // Calculate the reward amounts and transfer them to the reward vault
        uint256 totalLp = totalLP();
        for (uint i = 0; i < tokens.length; i++) {
            if (!whitelistedRewardTokens[tokens[i]]) revert TokenNotWhitelisted(tokens[i]);
            rewardsAmounts[i] = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
            IERC20Upgradeable(tokens[i]).safeTransfer(rewardVault, (rewardsAmounts[i] * totalLp) / totalLp);
        }
        // Emit an event for collecting rewards
        emit GetReward(tokens, rewardsAmounts);
    }

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

    function balanceOfToken(address token) internal view returns (uint256) {
        return IERC20Upgradeable(token).balanceOf(address(this));
    }

    ////////////////////////// View Functions //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function totalLP() public view returns (uint256) {
        uint256 freeLp = IERC20Upgradeable(pool).balanceOf(address(this));
        uint256 stakedLp = IGauge(gauge).balanceOf(address(this));
        return freeLp + stakedLp;
    }

    function boostPrice() public view returns (uint256 price) {
        uint256 amountOut = IPair(pool).current(boost, 10 ** boostDecimals);
        price = amountOut / 10 ** (usdDecimals - PRICE_DECIMALS);
    }
}
