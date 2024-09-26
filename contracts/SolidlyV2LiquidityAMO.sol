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
    error TokenNotWhitelisted(address token);
    error UsdAmountOutMismatch(uint256 routerOutput, uint256 balanceChange);
    error LpAmountOutMismatch(uint256 routerOutput, uint256 balanceChange);
    error PriceNotInRange(uint256 price);
    error InvalidReserveRatio(uint256 ratio);

    /* ========== ROLES ========== */
    /// @inheritdoc ISolidlyV2LiquidityAMO
    bytes32 public constant override SETTER_ROLE = keccak256("SETTER_ROLE");
    /// @inheritdoc ISolidlyV2LiquidityAMO
    bytes32 public constant override AMO_ROLE = keccak256("AMO_ROLE");
    /// @inheritdoc ISolidlyV2LiquidityAMO
    bytes32 public constant override REWARD_COLLECTOR_ROLE = keccak256("REWARD_COLLECTOR_ROLE");
    /// @inheritdoc ISolidlyV2LiquidityAMO
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @inheritdoc ISolidlyV2LiquidityAMO
    bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    /// @inheritdoc ISolidlyV2LiquidityAMO
    bytes32 public constant override WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /* ========== VARIABLES ========== */
    /// @inheritdoc ISolidlyV2LiquidityAMO
    address public override boost;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    address public override usd;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    address public override pool;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    uint256 public override boostDecimals;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    uint256 public override usdDecimals;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    address public override boostMinter;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    address public override router;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    address public override gauge;

    /// @inheritdoc ISolidlyV2LiquidityAMO
    address public override rewardVault;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    address public override treasuryVault;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    uint256 public override boostMultiplier;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    uint24 public override validRangeRatio;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    uint24 public override validRemovingRatio;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    uint24 public override dryPowderRatio;
    /// @inheritdoc ISolidlyV2LiquidityAMO
    mapping(address => bool) public override whitelistedRewardTokens;

    uint256 public boostLowerPriceSell;
    uint256 public boostUpperPriceBuy;
    uint256 public boostSellRatio;
    uint256 public usdBuyRatio;
    uint256 public tokenId;
    bool public useTokenId;

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
        address treasuryVault_,
        uint256 tokenId_,
        bool useTokenId_,
        uint256 boostMultiplier_,
        uint24 validRangeRatio_,
        uint24 validRemovingRatio_,
        uint24 dryPowderRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_,
        uint256 boostSellRatio_,
        uint256 usdBuyRatio_
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        if (
            admin == address(0) ||
            boost_ == address(0) ||
            usd_ == address(0) ||
            boostMinter_ == address(0) ||
            router_ == address(0) ||
            gauge_ == address(0)
        ) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        boost = boost_;
        usd = usd_;
        pool = ISolidlyRouter(router_).pairFor(usd, boost, true);
        boostDecimals = IERC20Metadata(boost).decimals();
        usdDecimals = IERC20Metadata(usd).decimals();
        boostMinter = boostMinter_;
        router = router_;
        gauge = gauge_;

        _grantRole(SETTER_ROLE, msg.sender);
        setVaults(rewardVault_, treasuryVault_);
        setTokenId(tokenId_, useTokenId_);
        setParams(
            boostMultiplier_,
            validRangeRatio_,
            validRemovingRatio_,
            dryPowderRatio_,
            boostLowerPriceSell_,
            boostUpperPriceBuy_,
            boostSellRatio_,
            usdBuyRatio_
        );
        _revokeRole(SETTER_ROLE, msg.sender);
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function unpause() external override onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// SETTER_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setVaults(address rewardVault_, address treasuryVault_) public override onlyRole(SETTER_ROLE) {
        if (rewardVault_ == address(0) || treasuryVault_ == address(0)) revert ZeroAddress();
        rewardVault = rewardVault_;
        treasuryVault = treasuryVault_;
        emit VaultsSet(rewardVault, treasuryVault);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setParams(
        uint256 boostMultiplier_,
        uint24 validRangeRatio_,
        uint24 validRemovingRatio_,
        uint24 dryPowderRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_,
        uint256 boostSellRatio_,
        uint256 usdBuyRatio_
    ) public override onlyRole(SETTER_ROLE) {
        if (validRangeRatio_ > FACTOR || validRemovingRatio_ > FACTOR || dryPowderRatio_ > FACTOR)
            revert InvalidRatioValue();
        boostMultiplier = boostMultiplier_;
        validRangeRatio = validRangeRatio_;
        validRemovingRatio = validRemovingRatio_;
        dryPowderRatio = dryPowderRatio_;
        boostLowerPriceSell = boostLowerPriceSell_;
        boostUpperPriceBuy = boostUpperPriceBuy_;
        boostSellRatio = boostSellRatio_;
        usdBuyRatio = usdBuyRatio_;
        emit ParamsSet(
            boostMultiplier,
            validRangeRatio,
            validRemovingRatio,
            dryPowderRatio,
            boostLowerPriceSell,
            boostUpperPriceBuy,
            boostSellRatio,
            usdBuyRatio
        );
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setWhitelistedTokens(address[] memory tokens, bool isWhitelisted) public override onlyRole(SETTER_ROLE) {
        for (uint i = 0; i < tokens.length; i++) {
            whitelistedRewardTokens[tokens[i]] = isWhitelisted;
        }
        emit RewardTokensSet(tokens, isWhitelisted);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function setTokenId(uint256 tokenId_, bool useTokenId_) public override onlyRole(SETTER_ROLE) {
        tokenId = tokenId_;
        useTokenId = useTokenId_;
        emit TokenIdSet(tokenId, useTokenId);
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    function _mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) internal returns (uint256 usdAmountOut, uint256 dryPowderAmount) {
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

        emit MintSell(boostAmount, usdAmountOut, dryPowderAmount);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
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
        returns (uint256 usdAmountOut, uint256 dryPowderAmount)
    {
        (usdAmountOut, dryPowderAmount) = _mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);
    }

    function _addLiquidityAndDeposit(
        uint256 tokenId_,
        bool useTokenId_,
        uint256 usdAmount,
        uint256 minUsdSpend,
        uint256 minLpAmount,
        uint256 deadline
    ) internal returns (uint256 boostSpent, uint256 usdSpent, uint256 lpAmount) {
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

        // Revoke approval from the router
        IERC20Upgradeable(boost).approve(router, 0);
        IERC20Upgradeable(usd).approve(router, 0);

        // Ensure the liquidity tokens minted are greater than or equal to the minimum required
        if (lpAmount < minLpAmount) revert InsufficientOutputAmount(lpAmount, minLpAmount);

        // Calculate the valid range for USD spent based on the BOOST spent and the validRangeRatio
        uint256 validRange = (boostSpent * validRangeRatio) / FACTOR;
        if (toBoostAmount(usdSpent) < boostSpent - validRange || toBoostAmount(usdSpent) > boostSpent + validRange)
            revert InvalidRatioToAddLiquidity();

        // Approve the transfer of liquidity tokens to the gauge and deposit them
        IERC20Upgradeable(pool).approve(gauge, lpAmount);
        if (useTokenId_) {
            IGauge(gauge).deposit(lpAmount, tokenId_);
        } else {
            IGauge(gauge).deposit(lpAmount);
        }

        // Burn excessive boosts
        if (boostAmount > boostSpent) IBoostStablecoin(boost).burn(boostAmount - boostSpent);

        emit AddLiquidityAndDeposit(boostSpent, usdSpent, lpAmount, tokenId_);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function addLiquidityAndDeposit(
        uint256 tokenId_,
        bool useTokenId_,
        uint256 usdAmount,
        uint256 minUsdSpend,
        uint256 minLpAmount,
        uint256 deadline
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostSpent, uint256 usdSpent, uint256 lpAmount)
    {
        (boostSpent, usdSpent, lpAmount) = _addLiquidityAndDeposit(
            tokenId_,
            useTokenId_,
            usdAmount,
            minUsdSpend,
            minLpAmount,
            deadline
        );
    }

    function _mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 tokenId_,
        bool useTokenId_,
        uint256 minUsdSpend,
        uint256 minLpAmount,
        uint256 deadline
    )
        internal
        returns (uint256 usdAmountOut, uint256 dryPowderAmount, uint256 boostSpent, uint256 usdSpent, uint256 lpAmount)
    {
        (usdAmountOut, dryPowderAmount) = _mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);
        uint256 price = boostPrice();
        if (price > FACTOR - validRangeRatio && price < FACTOR + validRangeRatio) {
            uint256 usdBalance = balanceOfToken(usd);
            (boostSpent, usdSpent, lpAmount) = _addLiquidityAndDeposit(
                tokenId_,
                useTokenId_,
                usdBalance,
                minUsdSpend,
                minLpAmount,
                deadline
            );
        }
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 tokenId_,
        bool useTokenId_,
        uint256 minUsdSpend,
        uint256 minLpAmount,
        uint256 deadline
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 usdAmountOut, uint256 dryPowderAmount, uint256 boostSpent, uint256 usdSpent, uint256 lpAmount)
    {
        (usdAmountOut, dryPowderAmount, boostSpent, usdSpent, lpAmount) = _mintSellFarm(
            boostAmount,
            minUsdAmountOut,
            tokenId_,
            useTokenId_,
            minUsdSpend,
            minLpAmount,
            deadline
        );
    }

    function _unfarmBuyBurn(
        uint256 lpAmount,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    ) internal returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut) {
        // Withdraw the specified amount of liquidity tokens from the gauge
        IGauge(gauge).withdraw(lpAmount);

        // Approve the transfer of liquidity tokens to the router for removal
        IERC20Upgradeable(pool).approve(router, lpAmount);

        uint256 usdBalanceBefore = balanceOfToken(usd);
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
        uint256 usdBalanceAfter = balanceOfToken(usd);

        if (usdRemoved != usdBalanceAfter - usdBalanceBefore)
            revert UsdAmountOutMismatch(usdRemoved, usdBalanceAfter - usdBalanceBefore);

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

        emit UnfarmBuyBurn(boostRemoved, usdRemoved, lpAmount, boostAmountOut);
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
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut)
    {
        (boostRemoved, usdRemoved, boostAmountOut) = _unfarmBuyBurn(
            lpAmount,
            minBoostRemove,
            minUsdRemove,
            minBoostAmountOut,
            deadline
        );
    }

    ////////////////////////// PUBLIC FUNCTIONS //////////////////////////
    function mintSellFarm() external whenNotPaused nonReentrant returns (uint256 lpAmount, uint256 newBoostPrice) {
        (uint256 reserve0, uint256 reserve1, ) = IPair(pool).getReserves();
        uint256 boostReserve;
        uint256 usdReserve;
        if (boost < usd) {
            boostReserve = reserve0;
            usdReserve = toBoostAmount(reserve1); // scaled
        } else {
            boostReserve = reserve1;
            usdReserve = toBoostAmount(reserve0); // scaled
        }
        // Checks if the expected boost price is more than 1$
        if (usdReserve <= boostReserve) revert InvalidReserveRatio({ratio: (FACTOR * usdReserve) / boostReserve});

        uint256 boostAmountIn = (((usdReserve - boostReserve) / 2) * boostSellRatio) / FACTOR;

        (, , , , lpAmount) = _mintSellFarm(
            boostAmountIn,
            toUsdAmount(boostAmountIn), // minUsdAmountOut
            tokenId,
            useTokenId,
            1, // minUsdSpend
            1, // minLpAmount
            block.timestamp + 1 // deadline
        );

        newBoostPrice = boostPrice();

        // Checks if the price of boost is greater than the boostLowerPriceSell
        if (newBoostPrice < boostLowerPriceSell) revert PriceNotInRange(newBoostPrice);

        emit PublicMintSellFarmExecuted(lpAmount, newBoostPrice);
    }

    function unfarmBuyBurn() external whenNotPaused nonReentrant returns (uint256 lpAmount, uint256 newBoostPrice) {
        (uint256 reserve0, uint256 reserve1, ) = IPair(pool).getReserves();
        uint256 boostReserve;
        uint256 usdReserve;
        if (boost < usd) {
            boostReserve = reserve0;
            usdReserve = toBoostAmount(reserve1); // scaled
        } else {
            boostReserve = reserve1;
            usdReserve = toBoostAmount(reserve0); // scaled
        }

        if (boostReserve <= usdReserve) revert InvalidReserveRatio({ratio: (FACTOR * usdReserve) / boostReserve});

        uint256 usdNeeded = (((boostReserve - usdReserve) / 2) * usdBuyRatio) / FACTOR;
        uint256 totalLp = IERC20Upgradeable(pool).totalSupply();
        lpAmount = (usdNeeded * totalLp) / usdReserve;

        // Readjust the LP amount and USD needed to balance price before removing LP
        lpAmount -= lpAmount ** 2 / totalLp;

        _unfarmBuyBurn(
            lpAmount,
            (lpAmount * boostReserve) / totalLp, // minBoostRemove
            toUsdAmount(usdNeeded), // minUsdRemove
            usdNeeded, // minBoostAmountOut
            block.timestamp + 1 //deadline
        );

        newBoostPrice = boostPrice();

        // Checks if the price of boost is less than the boostUpperPriceBuy
        if (newBoostPrice > boostUpperPriceBuy) revert PriceNotInRange(newBoostPrice);

        emit PublicUnfarmBuyBurnExecuted(lpAmount, newBoostPrice);
    }

    ////////////////////////// REWARD_COLLECTOR_ROLE ACTIONS //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function getReward(
        address[] memory tokens,
        bool passTokens
    ) external override onlyRole(REWARD_COLLECTOR_ROLE) whenNotPaused nonReentrant {
        _getReward(tokens, passTokens);
    }

    ////////////////////////// Withdrawal functions //////////////////////////
    /// @inheritdoc ISolidlyV2LiquidityAMO
    function withdrawERC20(
        address token,
        uint256 amount,
        address recipient
    ) external override onlyRole(WITHDRAWER_ROLE) {
        IERC20Upgradeable(token).safeTransfer(recipient, amount);
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function withdrawERC721(
        address token,
        uint256 tokenId_,
        address recipient
    ) external override onlyRole(WITHDRAWER_ROLE) {
        IERC721Upgradeable(token).safeTransferFrom(address(this), recipient, tokenId_);
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
        for (uint i = 0; i < tokens.length; i++) {
            if (!whitelistedRewardTokens[tokens[i]]) revert TokenNotWhitelisted(tokens[i]);
            rewardsAmounts[i] = IERC20Upgradeable(tokens[i]).balanceOf(address(this));
            IERC20Upgradeable(tokens[i]).safeTransfer(rewardVault, rewardsAmounts[i]);
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
    function totalLP() external view override returns (uint256) {
        uint256 freeLp = IERC20Upgradeable(pool).balanceOf(address(this));
        uint256 stakedLp = IGauge(gauge).balanceOf(address(this));
        return freeLp + stakedLp;
    }

    /// @inheritdoc ISolidlyV2LiquidityAMO
    function boostPrice() public view override returns (uint256 price) {
        uint256 amountOut = IPair(pool).current(boost, 10 ** boostDecimals);
        price = amountOut / 10 ** (usdDecimals - PRICE_DECIMALS);
    }
}
