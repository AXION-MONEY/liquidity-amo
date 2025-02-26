// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./MasterAMO.sol";
import {IGauge} from "./interfaces/v2/IGauge.sol";
import {ISolidlyRouter} from "./interfaces/v2/ISolidlyRouter.sol";
import {IPair} from "./interfaces/v2/IPair.sol";
import {IV2AMO} from "./interfaces/v2/IV2AMO.sol";
import {IVRouter} from "./interfaces/v2/IVRouter.sol";
import {IPoolFactory} from "./interfaces/v2/IPoolFactory.sol";
import {IPairFactory} from "./interfaces/v2/IPairFactory.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
* @title V2AMO Contract
* @notice Implements Automated Market Operations (AMO) for V2 pools protocols.
* @dev Inherits from MasterAMO and implements the IV2AMO interface. All errors, events and public state variable
        documentation are declared in the interface.
*/
contract V2AMO is IV2AMO, MasterAMO {
    using SafeERC20 for IERC20;
    // -------------------------------------------------------------
    //                             ROLES
    // -------------------------------------------------------------
    /// @inheritdoc IV2AMO
    bytes32 public constant override REWARD_COLLECTOR_ROLE = keccak256("REWARD_COLLECTOR_ROLE");

    // -------------------------------------------------------------
    //                         STATE VARIABLES
    // -------------------------------------------------------------

    ////// MUTABLE //////
    /// @inheritdoc IV2AMO
    bool public override stable;
    /// @inheritdoc IV2AMO
    PoolType public override poolType;
    /// @inheritdoc IV2AMO
    address public override factory;
    /// @inheritdoc IV2AMO
    address public override router;
    /// @inheritdoc IV2AMO
    address public override gauge;
    /// @inheritdoc IV2AMO
    uint256 public override poolFee;
    /// @inheritdoc IV2AMO
    address public override rewardVault;
    /// @inheritdoc IV2AMO
    mapping(address => bool) public override whitelistedRewardTokens;
    /// @inheritdoc IV2AMO
    uint256 public override boostSellRatio;
    /// @inheritdoc IV2AMO
    uint256 public override usdBuyRatio;
    /// @inheritdoc IV2AMO
    uint256 public override tokenId;
    /// @inheritdoc IV2AMO
    bool public override useTokenId;

    // -------------------------------------------------------------
    //                        INITIALIZATION
    // -------------------------------------------------------------
    /**
     * @notice Constructor disables initializers.
     * @dev Required for upgradeable contracts.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the V2AMO contract.
     * @param admin Address with admin privileges.
     * @param boost_ Address of the BOOST token.
     * @param usd_ Address of the USD token.
     * @param stable_ True if the pool is stable; false if volatile.
     * @param poolType_ The pool type (SOLIDLY_V2, VELO_LIKE or EQUAL_LIKE).
     * @param boostMinter_ Address of the BOOST minter contract.
     * @param priceManager_ Address of the price manager contract.
     * @param pairedTokenType_ The paired token type.
     * @param factory_ Address of the factory (if zero, the default factory is used for VELO_LIKE pools).
     * @param router_ Address of the router contract.
     * @param gauge_ Address of the gauge contract.
     * @param rewardVault_ Address of the reward vault.
     * @param tokenId_ The token ID to be used when depositing liquidity.
     * @param useTokenId_ Boolean indicating whether to use the token ID.
     * @param boostMultiplier_ Multiplier used to calculate BOOST amount to mint in addLiquidity().
     * @param validRangeWidth_ Valid range width for liquidity addition.
     * @param validRemovingRatio_ Valid ratio for liquidity removal.
     * @param boostLowerPriceSell_ Lower price threshold for selling BOOST.
     * @param boostUpperPriceBuy_ Upper price threshold for buying BOOST.
     * @param boostSellRatio_ BOOST sell ratio.
     * @param usdBuyRatio_ USD buy ratio.
     */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        bool stable_,
        PoolType poolType_,
        address boostMinter_,
        address priceManager_,
        PairedTokenType pairedTokenType_,
        address factory_,
        address router_,
        address gauge_,
        address rewardVault_,
        uint256 tokenId_,
        bool useTokenId_,
        uint256 boostMultiplier_,
        uint24 validRangeWidth_,
        uint24 validRemovingRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_,
        uint256 boostSellRatio_,
        uint256 usdBuyRatio_
    ) public initializer {
        // Validate required addresses
        if (router_ == address(0) || gauge_ == address(0)) revert ZeroAddress();

        poolType = poolType_;
        stable = stable_;
        address pool_;
        uint256 poolFee_;
        // For VELO_LIKE pools, determine factory and get pool address using the IVRouter
        if (poolType == PoolType.VELO_LIKE) {
            if (factory_ == address(0)) {
                factory = IVRouter(router_).defaultFactory();
            } else {
                factory = factory_;
            }
            pool_ = IVRouter(router_).poolFor(usd_, boost_, stable_, factory);
            poolFee_ = IPoolFactory(factory).getFee(pool_, stable_);
        } else {
            // For SOLIDLY_V2 and EQUAL_LIKE pools
            pool_ = ISolidlyRouter(router_).pairFor(usd_, boost_, stable_);
            factory = ISolidlyRouter(router_).factory();
            poolFee_ = IPairFactory(factory).getFee(stable_);
        }

        // Initialize inherited variables from MasterAMO
        super.initialize(admin, boost_, usd_, pool_, boostMinter_, priceManager_, pairedTokenType_);

        router = router_;
        gauge = gauge_;
        uint256 feeScaledFactor = poolType == PoolType.EQUAL_LIKE ? 1e18 : 1e4;
        _grantRole(SETTER_ROLE, msg.sender);
        setPoolFee((poolFee_ * FACTOR) / feeScaledFactor);
        setVault(rewardVault_);
        setTokenId(tokenId_, useTokenId_);
        setParams(
            boostMultiplier_,
            validRangeWidth_,
            validRemovingRatio_,
            boostLowerPriceSell_,
            boostUpperPriceBuy_,
            boostSellRatio_,
            usdBuyRatio_
        );
        _revokeRole(SETTER_ROLE, msg.sender);
    }

    // -------------------------------------------------------------
    //                   SETTER_ROLE ACTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IV2AMO
    function setPoolFee(uint256 poolFee_) public override onlyRole(SETTER_ROLE) {
        poolFee = poolFee_;
        emit PoolFeeSet(poolFee);
    }

    /// @inheritdoc IV2AMO
    function setVault(address rewardVault_) public override onlyRole(SETTER_ROLE) {
        if (rewardVault_ == address(0)) revert ZeroAddress();
        rewardVault = rewardVault_;
        emit VaultSet(rewardVault);
    }

    /// @inheritdoc IV2AMO
    function setTokenId(uint256 tokenId_, bool useTokenId_) public override onlyRole(SETTER_ROLE) {
        tokenId = tokenId_;
        useTokenId = useTokenId_;
        emit TokenIdSet(tokenId, useTokenId);
    }

    /// @inheritdoc IV2AMO
    function setParams(
        uint256 boostMultiplier_,
        uint24 validRangeWidth_,
        uint24 validRemovingRatio_,
        uint256 boostLowerPriceSell_,
        uint256 boostUpperPriceBuy_,
        uint256 boostSellRatio_,
        uint256 usdBuyRatio_
    ) public override onlyRole(SETTER_ROLE) {
        // Ensure valid ratios (validRangeWidth must be lower than FACTOR; validRemovingRatio must be greater than FACTOR)
        if (validRangeWidth_ > FACTOR || validRemovingRatio_ < FACTOR) revert InvalidRatioValue();
        boostMultiplier = boostMultiplier_;
        validRangeWidth = validRangeWidth_;
        validRemovingRatio = validRemovingRatio_;
        boostLowerPriceSell = boostLowerPriceSell_;
        boostUpperPriceBuy = boostUpperPriceBuy_;
        boostSellRatio = boostSellRatio_;
        usdBuyRatio = usdBuyRatio_;
        emit ParamsSet(
            boostMultiplier,
            validRangeWidth,
            validRemovingRatio,
            boostLowerPriceSell,
            boostUpperPriceBuy,
            boostSellRatio,
            usdBuyRatio
        );
    }

    /// @inheritdoc IV2AMO
    function setWhitelistedTokens(address[] memory tokens, bool isWhitelisted) external override onlyRole(SETTER_ROLE) {
        for (uint256 i = 0; i < tokens.length; i++) {
            whitelistedRewardTokens[tokens[i]] = isWhitelisted;
        }
        emit RewardTokensSet(tokens, isWhitelisted);
    }

    // -------------------------------------------------------------
    //                INTERNAL HELPER VIEW FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc MasterAMO
    function _validateSwap(bool boostForUsd) internal view override {
        (uint256 boostReserve, uint256 usdReserve) = getReserves();
        uint256 price = boostPrice();
        uint256 boostTargetPrice = targetPrice();
        if (boostForUsd) {
            // mintSellFarm
            if ((boostReserve * boostTargetPrice) / FACTOR >= usdReserve)
                revert InvalidReserveRatio({ratio: (FACTOR * usdReserve) / boostReserve});
            if (price <= priceUpperBound(boostTargetPrice)) revert PriceAlreadyInRange(price);
        } else {
            // unfarmBuyBurn
            if (usdReserve >= (boostReserve * boostTargetPrice) / FACTOR)
                revert InvalidReserveRatio({ratio: (FACTOR * usdReserve) / boostReserve});
            if (price >= priceLowerBound(boostTargetPrice)) revert PriceAlreadyInRange(price);
        }
    }

    // -------------------------------------------------------------
    //                INTERNAL FUNCTIONS
    // -------------------------------------------------------------

    ////// MINT-SELL-FARM FUNCTIONS //////

    /// @inheritdoc MasterAMO
    function _mintAndSellBoost(
        uint256 boostAmount
    ) internal override returns (uint256 boostAmountIn, uint256 usdAmountOut) {
        // Mint BOOST tokens to this contract
        IMinter(boostMinter).protocolMint(address(this), boostAmount);
        uint256 boostTargetPrice = targetPrice();
        // Approve router to spend BOOST
        IERC20(boost).approve(router, boostAmount);
        // Adjust BOOST amount for pool fee
        uint256 boostAmountWithoutFee = boostAmount - ((boostAmount * poolFee) / FACTOR);
        // Calculate minimum expected USD output based on target price
        uint256 minUsdAmountOut = (toUsdAmount(boostAmountWithoutFee) * boostTargetPrice) / FACTOR;
        uint256 usdBalanceBefore = balanceOfToken(usd);

        uint256[] memory amounts;
        if (poolType == PoolType.VELO_LIKE) {
            // For VELO_LIKE pools, use IVRouter for swapping
            IVRouter.Route[] memory routes = new IVRouter.Route[](1);
            routes[0] = IVRouter.Route({from: boost, to: usd, stable: stable, factory: factory});
            amounts = IVRouter(router).swapExactTokensForTokens(
                boostAmount,
                minUsdAmountOut,
                routes,
                address(this),
                block.timestamp + 1
            );
        } else {
            // For SOLIDLY_V2 pools, use the Solidly router
            ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](1);
            routes[0] = ISolidlyRouter.route({from: boost, to: usd, stable: stable});
            amounts = ISolidlyRouter(router).swapExactTokensForTokens(
                boostAmount,
                minUsdAmountOut,
                routes,
                address(this),
                block.timestamp + 1
            );
        }
        boostAmountIn = amounts[0];
        usdAmountOut = amounts[1];

        uint256 usdBalanceAfter = balanceOfToken(usd);
        if (usdAmountOut != usdBalanceAfter - usdBalanceBefore)
            revert UsdAmountOutMismatch(usdAmountOut, usdBalanceAfter - usdBalanceBefore);
        if (usdAmountOut < minUsdAmountOut) revert InsufficientOutputAmount(usdAmountOut, minUsdAmountOut);
        uint256 price = boostPrice();
        if (price <= priceLowerBound(boostTargetPrice)) revert PriceNotInRange(price);
        emit MintSell(boostAmount, usdAmountOut);
    }

    /// @inheritdoc MasterAMO
    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend
    ) internal override returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity) {
        // Only add liquidity when current BOOST price is within the valid range.
        uint256 price = boostPrice();
        uint256 boostTargetPrice = targetPrice();
        if (price <= priceLowerBound(boostTargetPrice) || price >= priceUpperBound(boostTargetPrice))
            revert InvalidRatioToAddLiquidity();

        // Calculate BOOST amount to mint based on the USD amount and multiplier.
        uint256 boostAmount = (toBoostAmount(usdAmount) * boostMultiplier) / FACTOR;
        IMinter(boostMinter).protocolMint(address(this), boostAmount);

        // Approve router for BOOST and USD transfers.
        IERC20(boost).approve(router, boostAmount);
        IERC20(usd).forceApprove(router, usdAmount);

        uint256 lpBalanceBefore = balanceOfToken(pool);
        // Add liquidity using the Solidly router.
        (boostSpent, usdSpent, liquidity) = ISolidlyRouter(router).addLiquidity(
            boost,
            usd,
            stable,
            boostAmount,
            usdAmount,
            minBoostSpend,
            minUsdSpend,
            address(this),
            block.timestamp + 1
        );
        uint256 lpBalanceAfter = balanceOfToken(pool);
        if (liquidity != lpBalanceAfter - lpBalanceBefore)
            revert LpAmountOutMismatch(liquidity, lpBalanceAfter - lpBalanceBefore);

        // Revoke approvals for security.
        IERC20(boost).approve(router, 0);
        IERC20(usd).forceApprove(router, 0);

        // Deposit liquidity into the gauge.
        IERC20(pool).approve(gauge, liquidity);
        if (useTokenId) {
            IGauge(gauge).deposit(liquidity, tokenId);
        } else {
            IGauge(gauge).deposit(liquidity);
        }

        // Burn any excessive minted BOOST.
        if (boostAmount > boostSpent) IBoostStablecoin(boost).burn(boostAmount - boostSpent);
        emit AddLiquidityAndDeposit(boostSpent, usdSpent, liquidity, tokenId);
    }

    /// @inheritdoc MasterAMO
    function _mintSellFarm() internal override returns (uint256 liquidity, uint256 newBoostPrice) {
        (uint256 boostReserve, uint256 usdReserve) = getReserves();
        uint256 boostAmountIn = ((Math.sqrt((usdReserve * boostReserve * FACTOR) / targetPrice()) - boostReserve) *
            boostSellRatio) / FACTOR;
        boostAmountIn += (boostAmountIn * poolFee) / (FACTOR - poolFee);
        (, , , , liquidity) = _mintSellFarm(
            boostAmountIn,
            1, // minBoostSpend
            1 // minUsdSpend
        );
        newBoostPrice = boostPrice();
    }

    ////// UNFARM-BUY-BURN FUNCTIONS //////

    /// @inheritdoc MasterAMO
    function _unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove
    )
        internal
        override
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut)
    {
        // Withdraw LP tokens from the gauge.
        IGauge(gauge).withdraw(liquidity);
        IERC20(pool).approve(router, liquidity);

        uint256 usdBalanceBefore = balanceOfToken(usd);

        (boostRemoved, usdRemoved) = ISolidlyRouter(router).removeLiquidity(
            boost,
            usd,
            stable,
            liquidity,
            minBoostRemove,
            minUsdRemove,
            address(this),
            block.timestamp + 300
        );
        uint256 boostTargetPrice = targetPrice();
        uint256 usdBalanceAfter = balanceOfToken(usd);
        if (usdRemoved != usdBalanceAfter - usdBalanceBefore)
            revert UsdAmountOutMismatch(usdRemoved, usdBalanceAfter - usdBalanceBefore);
        if ((((boostRemoved * validRemovingRatio) / FACTOR) * boostTargetPrice) / FACTOR < toBoostAmount(usdRemoved))
            revert InvalidRatioToRemoveLiquidity();

        // Approve router for the USD swap.
        IERC20(usd).forceApprove(router, usdRemoved);
        uint256[] memory amounts;
        uint256 usdRemovedWithoutFee = usdRemoved - ((usdRemoved * poolFee) / FACTOR);
        uint256 minBoostAmountOut = (toBoostAmount(usdRemovedWithoutFee) * FACTOR) / boostTargetPrice;
        if (poolType == PoolType.VELO_LIKE) {
            IVRouter.Route[] memory routes = new IVRouter.Route[](1);
            routes[0] = IVRouter.Route({from: usd, to: boost, stable: stable, factory: factory});
            amounts = IVRouter(router).swapExactTokensForTokens(
                usdRemoved,
                minBoostAmountOut,
                routes,
                address(this),
                block.timestamp + 300
            );
        } else {
            ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](1);
            routes[0] = ISolidlyRouter.route(usd, boost, stable);
            amounts = ISolidlyRouter(router).swapExactTokensForTokens(
                usdRemoved,
                minBoostAmountOut,
                routes,
                address(this),
                block.timestamp + 300
            );
        }
        uint256 price = boostPrice();
        if (price >= priceUpperBound(boostTargetPrice)) revert PriceNotInRange(price);
        usdAmountIn = amounts[0];
        boostAmountOut = amounts[1];
        IBoostStablecoin(boost).burn(boostRemoved + boostAmountOut);
        emit UnfarmBuyBurn(boostRemoved, usdRemoved, liquidity, boostAmountOut);
    }

    /// @inheritdoc MasterAMO
    function _unfarmBuyBurn() internal override returns (uint256 liquidity, uint256 newBoostPrice) {
        (uint256 boostReserve, uint256 usdReserve) = getReserves();
        uint256 totalLp = IERC20(pool).totalSupply();
        uint256 sqrtResRatio = Math.sqrt((FACTOR ** 2 * usdReserve) / ((boostReserve * targetPrice()) / FACTOR));
        uint256 removalPercentage = (FACTOR * (FACTOR - sqrtResRatio)) / (FACTOR - ((poolFee * sqrtResRatio) / FACTOR));
        liquidity = (totalLp * removalPercentage) / FACTOR;
        liquidity = (liquidity * usdBuyRatio) / FACTOR;
        _unfarmBuyBurn(
            liquidity,
            (liquidity * boostReserve) / totalLp, // minBoostRemove
            toUsdAmount((liquidity * usdReserve) / totalLp) // minUsdRemove, recalculated to cover precision loss
        );
        newBoostPrice = boostPrice();
    }

    // -------------------------------------------------------------
    //                     EXTERNAL FUNCTIONS
    // -------------------------------------------------------------

    ////// REWARD_COLLECTOR_ROLE ACTIONS //////

    /// @inheritdoc IV2AMO
    function getReward(
        address[] memory tokens,
        bool passTokens
    ) external override onlyRole(REWARD_COLLECTOR_ROLE) whenNotPaused nonReentrant {
        uint256[] memory rewardsAmounts = new uint256[](tokens.length);
        if (poolType == PoolType.VELO_LIKE) {
            IGauge(gauge).getReward(address(this));
        } else if (passTokens) {
            IGauge(gauge).getReward(address(this), tokens);
        } else {
            IGauge(gauge).getReward();
        }
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!whitelistedRewardTokens[tokens[i]]) revert TokenNotWhitelisted(tokens[i]);
            rewardsAmounts[i] = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).safeTransfer(rewardVault, rewardsAmounts[i]);
        }
        emit GetReward(tokens, rewardsAmounts);
    }

    // -------------------------------------------------------------
    //                    VIEW FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IMasterAMO
    function boostPrice() public view override returns (uint256 price) {
        if (!stable) {
            (uint256 boostReserve, uint256 usdReserve) = getReserves();
            price = (10 ** PRICE_DECIMALS * usdReserve) / boostReserve;
        } else {
            uint256 amountIn = 10 ** boostDecimals;
            amountIn += (amountIn * poolFee) / FACTOR;
            uint256 amountOut = IPair(pool).getAmountOut(amountIn, boost);
            if (usdDecimals > PRICE_DECIMALS) {
                price = amountOut / 10 ** (usdDecimals - PRICE_DECIMALS);
            } else {
                price = amountOut * 10 ** (PRICE_DECIMALS - usdDecimals);
            }
        }
    }

    /// @inheritdoc IV2AMO
    function getReserves() public view override returns (uint256 boostReserve, uint256 usdReserve) {
        (uint256 reserve0, uint256 reserve1, ) = IPair(pool).getReserves();
        if (boost < usd) {
            boostReserve = reserve0;
            usdReserve = toBoostAmount(reserve1);
        } else {
            boostReserve = reserve1;
            usdReserve = toBoostAmount(reserve0);
        }
    }
}
