// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";
import {IGauge} from "./interfaces/v2/IGauge.sol";
import {ISolidlyV2LiquidityAMO} from "./interfaces/v2/ISolidlyV2LiquidityAMO.sol";
import {ISolidlyRouter} from "./interfaces/v2/ISolidlyRouter.sol";

/// @title Liquidity AMO for BOOST-USD Solidly pair
/// @notice The LiquidityAMO contract is responsible for maintaining the BOOST-USD peg in Solidly pairs. It achieves this through minting and burning BOOST tokens, as well as adding and removing liquidity from the BOOST-USD pair.
contract SolidlyV2LiquidityAMO is
    ISolidlyV2LiquidityAMO,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== ROLES ========== */
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant AMO_ROLE = keccak256("AMO_ROLE");
    bytes32 public constant REWARD_COLLECTOR_ROLE = keccak256("REWARD_COLLECTOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /* ========== VARIABLES ========== */
    address public router;
    address public gauge;
    address public boost;
    address public boostMinter;
    address public usd;
    address public usd_boost;
    uint256 public usdDecimals;
    uint256 public boostDecimals;
    address public rewardVault;
    address public treasuryVault;
    uint256 public boostAmountLimit;
    uint256 public lpAmountLimit;
    uint256 public validRangeRatio; // decimals 6
    uint256 public boostMultiplier; // decimals 6
    uint256 public epsilon; // decimals 6
    uint256 public delta; // decimals 6
    mapping(address => bool) public whitelistedRewardTokens;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address router_,
        address gauge_,
        address boost_,
        address boostMinter_,
        address usd_,
        address rewardVault_,
        address treasuryVault_
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        require(
            admin != address(0) &&
                router_ != address(0) &&
                gauge_ != address(0) &&
                boost_ != address(0) &&
                usd_ != address(0) &&
                rewardVault_ != address(0) &&
                treasuryVault_ != address(0),
            "LiquidityAMO: ZERO_ADDRESS"
        );
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        router = router_;
        gauge = gauge_;
        boost = boost_;
        boostMinter = boostMinter_;
        usd = usd_;
        usd_boost = ISolidlyRouter(router).pairFor(usd, boost, true);
        usdDecimals = IERC20Metadata(usd).decimals();
        boostDecimals = IERC20Metadata(boost).decimals();
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
        require(rewardVault_ != address(0) && treasuryVault_ != address(0), "LiquidityAMO: ZERO_ADDRESS");
        rewardVault = rewardVault_;
        treasuryVault = treasuryVault_;

        emit SetVaults(rewardVault_, treasuryVault_);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setParams(
        uint256 boostAmountLimit_,
        uint256 lpAmountLimit_,
        uint256 validRangeRatio_,
        uint256 boostMultiplier_,
        uint256 delta_,
        uint256 epsilon_
    ) external onlyRole(SETTER_ROLE) {
        require(validRangeRatio_ <= 1e6, "LiquidityAMO: INVALID_RATIO_VALUE");
        boostAmountLimit = boostAmountLimit_;
        lpAmountLimit = lpAmountLimit_;
        validRangeRatio = validRangeRatio_;
        boostMultiplier = boostMultiplier_;
        delta = delta_;
        epsilon = epsilon_;
        emit SetParams(boostAmountLimit_, lpAmountLimit_, validRangeRatio_, boostMultiplier_, delta_, epsilon_);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setRewardToken(address[] memory tokens, bool isWhitelisted) external onlyRole(SETTER_ROLE) {
        for (uint i = 0; i < tokens.length; i++) {
            whitelistedRewardTokens[tokens[i]] = isWhitelisted;
        }
        emit SetRewardToken(tokens, isWhitelisted);
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) public onlyRole(AMO_ROLE) whenNotPaused returns (uint256 usdAmountOut, uint256 dryPowderAmount) {
        // Ensure the BOOST amount does not exceed the allowed limit
        require(boostAmount <= boostAmountLimit, "LiquidityAMO: BOOST_AMOUNT_LIMIT_EXCEEDED");

        // Mint the specified amount of BOOST tokens
        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of BOOST tokens to the router
        IERC20Upgradeable(boost).approve(router, boostAmount);

        // Define the route to swap BOOST tokens for USD tokens
        ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](1);
        routes[0] = ISolidlyRouter.route(boost, usd, true);

        // Execute the swap and store the amounts of tokens involved
        uint256[] memory amounts = ISolidlyRouter(router).swapExactTokensForTokens(
            boostAmount,
            boostAmount / (10 ** (boostDecimals - usdDecimals)) > minUsdAmountOut
                ? boostAmount / (10 ** (boostDecimals - usdDecimals))
                : minUsdAmountOut,
            routes,
            address(this),
            deadline
        );
        usdAmountOut = amounts[1];
        dryPowderAmount = (usdAmountOut * delta) / (10 ** 6);
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
        uint256 boostAmount;
        if (usdDecimals + 6 > boostDecimals) {
            boostAmount = (usdAmount * boostMultiplier) / (10 ** (usdDecimals + 6 - boostDecimals));
        } else {
            boostAmount = usdAmount * boostMultiplier * (10 ** (boostDecimals - usdDecimals - 6));
        }

        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve the transfer of BOOST and USD tokens to the router
        IERC20Upgradeable(boost).approve(router, boostAmount);
        IERC20Upgradeable(usd).approve(router, usdAmount);

        // Add liquidity to the BOOST-USD pool
        (boostSpent, usdSpent, lpAmount) = ISolidlyRouter(router).addLiquidity(
            boost,
            usd,
            true,
            boostAmount,
            usdAmount,
            minUsdSpend * (10 ** (boostDecimals - usdDecimals)),
            minUsdSpend,
            address(this),
            deadline
        );

        // Ensure the liquidity tokens minted are greater than or equal to the minimum required
        require(lpAmount >= minLpAmount, "LiquidityAMO: INSUFFICIENT_OUTPUT_LIQUIDITY");

        // Calculate the valid range for USD spent based on the BOOST spent and the validRangeRatio
        uint256 validRange = (boostSpent * validRangeRatio) / 1e6;
        require(
            usdSpent * (10 ** (boostDecimals - usdDecimals)) > boostSpent - validRange &&
                usdSpent * (10 ** (boostDecimals - usdDecimals)) < boostSpent + validRange,
            "LiquidityAMO: INVALID_RANGE_TO_ADD_LIQUIDITY"
        );

        // Approve the transfer of liquidity tokens to the gauge and deposit them
        IERC20Upgradeable(usd_boost).approve(gauge, lpAmount);
        if (useTokenId) {
            IGauge(gauge).deposit(lpAmount, tokenId);
        } else {
            IGauge(gauge).deposit(lpAmount);
        }

        // Burn excessive boosts
        IBoostStablecoin(boost).burn(boostAmount - boostSpent);

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
        uint256 usdBalance = usdAmountOut - dryPowderAmount;
        (boostSpent, usdSpent, lpAmount) = addLiquidityAndDeposit(
            tokenId,
            useTokenId,
            usdBalance,
            minUsdSpend,
            minLpAmount,
            deadline
        );
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
        require(lpAmount <= lpAmountLimit && lpAmount <= totalLP(), "LiquidityAMO: LP_AMOUNT_LIMIT_EXCEEDED");
        // Withdraw the specified amount of liquidity tokens from the gauge
        IGauge(gauge).withdraw(lpAmount);

        // Approve the transfer of liquidity tokens to the router for removal
        IERC20Upgradeable(usd_boost).approve(router, lpAmount);

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
        require(
            boostRemoved * epsilon >= usdRemoved * (10 ** (boostDecimals - usdDecimals + 6)),
            "LiquidityAMO: REMOVE_LIQUIDITY_WITH_WRONG_RATIO"
        );

        // Define the route to swap USD tokens for BOOST tokens
        ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](1);
        routes[0] = ISolidlyRouter.route(usd, boost, true);

        // Approve the transfer of usd tokens to the router
        IERC20Upgradeable(usd).approve(router, usdRemoved);

        // Execute the swap and store the amounts of tokens involved
        uint256[] memory amounts = ISolidlyRouter(router).swapExactTokensForTokens(
            usdRemoved,
            usdRemoved * (10 ** (boostDecimals - usdDecimals)) > minBoostAmountOut
                ? usdRemoved * (10 ** (boostDecimals - usdDecimals))
                : minBoostAmountOut,
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
            require(whitelistedRewardTokens[tokens[i]], "LiquidityAMO: NOT_WHITELISTED_REWARD_TOKEN");
            rewardsAmounts[i] = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
            IERC20Upgradeable(tokens[i]).safeTransfer(rewardVault, (rewardsAmounts[i] * totalLp) / totalLp);
        }
        // Emit an event for collecting rewards
        emit GetReward(tokens, rewardsAmounts);
    }

    ////////////////////////// View Functions //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function totalLP() public view returns (uint256) {
        uint256 freeLp = IERC20Upgradeable(usd_boost).balanceOf(address(this));
        uint256 stakedLp = IGauge(gauge).balanceOf(address(this));
        return freeLp + stakedLp;
    }
}
