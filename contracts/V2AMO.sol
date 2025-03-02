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
import {IIon} from "./interfaces/IIon.sol";

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
    bool public override isStablePool;
    /// @inheritdoc IV2AMO
    PoolType public override poolType;
    /// @inheritdoc IV2AMO
    address public override factoryAddress;
    /// @inheritdoc IV2AMO
    address public override routerAddress;
    /// @inheritdoc IV2AMO
    address public override gaugeAddress;
    /// @inheritdoc IV2AMO
    uint256 public override poolFee;
    /// @inheritdoc IV2AMO
    address public override rewardVault;
    /// @inheritdoc IV2AMO
    mapping(address => bool) public override whitelistedRewardTokens;
    /// @inheritdoc IV2AMO
    uint256 public override ionSellRatio;
    /// @inheritdoc IV2AMO
    uint256 public override pairTokenBuyRatio;
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
     * @param ionAddress_ Address of the ION token.
     * @param pairTokenAddress_ Address of the Pair token.
     * @param isStable_ True if the pool is stable; false if volatile.
     * @param poolType_ The pool type (SOLIDLY_V2, VELO_LIKE or EQUAL_LIKE).
     * @param ionMinterAddress_ Address of the ION minter contract.
     * @param priceManagerAddress_ Address of the price manager contract.
     * @param pairTokenType_ The type of the token paired with ION.
     * @param factoryAddress_ Address of the factory (if zero, the default factory is used for VELO_LIKE pools).
     * @param routerAddress_ Address of the router contract.
     * @param gaugeAddress_ Address of the gauge contract.
     * @param rewardVault_ Address of the reward vault.
     * @param tokenId_ The token ID to be used when depositing liquidity.
     * @param useTokenId_ Boolean indicating whether to use the token ID.
     * @param ionMultiplier_ Multiplier used to calculate ION amount to mint in addLiquidity().
     * @param validRangeWidth_ Valid range width for liquidity addition.
     * @param ionSellRatio_ ION sell ratio.
     * @param pairTokenBuyRatio_ PairToken buy ratio.
     */
    function initialize(
        address admin,
        address ionAddress_,
        address pairTokenAddress_,
        bool isStable_,
        PoolType poolType_,
        address ionMinterAddress_,
        address priceManagerAddress_,
        PairTokenType pairTokenType_,
        address factoryAddress_,
        address routerAddress_,
        address gaugeAddress_,
        address rewardVault_,
        uint256 tokenId_,
        bool useTokenId_,
        uint256 ionMultiplier_,
        uint24 validRangeWidth_,
        uint256 ionSellRatio_,
        uint256 pairTokenBuyRatio_
    ) public initializer {
        // Validate required addresses
        if (routerAddress_ == address(0) || gaugeAddress_ == address(0)) revert ZeroAddress();

        poolType = poolType_;
        isStablePool = isStable_;
        address pool_;
        uint256 poolFee_;
        // For VELO_LIKE pools, determine factory and get pool address using the IVRouter
        if (poolType == PoolType.VELO_LIKE) {
            if (factoryAddress_ == address(0)) {
                factoryAddress = IVRouter(routerAddress_).defaultFactory();
            } else {
                factoryAddress = factoryAddress_;
            }
            pool_ = IVRouter(routerAddress_).poolFor(pairTokenAddress_, ionAddress_, isStable_, factoryAddress);
            poolFee_ = IPoolFactory(factoryAddress).getFee(pool_, isStable_);
        } else {
            // For SOLIDLY_V2 and EQUAL_LIKE pools
            pool_ = ISolidlyRouter(routerAddress_).pairFor(pairTokenAddress_, ionAddress_, isStable_);
            factoryAddress = ISolidlyRouter(routerAddress_).factory();
            poolFee_ = IPairFactory(factoryAddress).getFee(isStable_);
        }

        // Initialize inherited variables from MasterAMO
        super.initialize(
            admin,
            ionAddress_,
            pairTokenAddress_,
            pool_,
            ionMinterAddress_,
            priceManagerAddress_,
            pairTokenType_
        );

        routerAddress = routerAddress_;
        gaugeAddress = gaugeAddress_;
        uint256 feeScaledFactor = poolType == PoolType.EQUAL_LIKE ? 1e18 : 1e4;
        _grantRole(SETTER_ROLE, msg.sender);
        setPoolFee((poolFee_ * FACTOR) / feeScaledFactor);
        setVault(rewardVault_);
        setTokenId(tokenId_, useTokenId_);
        setParams(ionMultiplier_, validRangeWidth_, ionSellRatio_, pairTokenBuyRatio_);
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
        uint256 ionMultiplier_,
        uint24 validRangeWidth_,
        uint256 ionSellRatio_,
        uint256 pairTokenBuyRatio_
    ) public override onlyRole(SETTER_ROLE) {
        if (validRangeWidth_ > FACTOR) revert InvalidRatioValue();
        ionMultiplayer = ionMultiplier_;
        validRangeWidth = validRangeWidth_;
        ionSellRatio = ionSellRatio_;
        pairTokenBuyRatio = pairTokenBuyRatio_;
        emit ParamsSet(ionMultiplayer, validRangeWidth, ionSellRatio, pairTokenBuyRatio);
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
    function _validateSwap(bool ionForUsd) internal view override {
        (uint256 ionReserve, uint256 pairTokenReserve) = getReserves();
        uint256 currentPrice = ionPrice();
        uint256 targetPrice = ionTargetPrice();
        if (ionForUsd) {
            // mintSellFarm
            if ((ionReserve * targetPrice) / FACTOR >= pairTokenReserve)
                revert InvalidReserveRatio({ratio: (FACTOR * pairTokenReserve) / ionReserve});
            if (currentPrice <= ionPriceUpperBound(targetPrice)) revert PriceAlreadyInRange(currentPrice);
        } else {
            // unfarmBuyBurn
            if (pairTokenReserve >= (ionReserve * targetPrice) / FACTOR)
                revert InvalidReserveRatio({ratio: (FACTOR * pairTokenReserve) / ionReserve});
            if (currentPrice >= ionPriceLowerBound(targetPrice)) revert PriceAlreadyInRange(currentPrice);
        }
    }

    // -------------------------------------------------------------
    //                INTERNAL FUNCTIONS
    // -------------------------------------------------------------

    ////// MINT-SELL-FARM FUNCTIONS //////

    /// @inheritdoc MasterAMO
    function _mintAndSell() internal override {
        // Calculating ION amount for mint and sell
        (uint256 ionReserve, uint256 pairTokenReserve) = getReserves();
        uint256 ionAmount = ((Math.sqrt((pairTokenReserve * ionReserve * FACTOR) / ionTargetPrice()) - ionReserve) *
            ionSellRatio) / FACTOR;
        ionAmount += (ionAmount * poolFee) / (FACTOR - poolFee);

        // Mint ION tokens to this contract
        IMinter(ionMinterAddress).protocolMint(address(this), ionAmount);
        uint256 targetPrice = ionTargetPrice();
        // Approve router to spend ION
        IERC20(ionAddress).approve(routerAddress, ionAmount);
        // Adjust ION amount for pool fee
        uint256 ionAmountWithoutFee = ionAmount - ((ionAmount * poolFee) / FACTOR);
        // Calculate minimum expected USD output based on target price
        uint256 minPairTokenAmountOut = (scaleIonToPairTokenDecimals(ionAmountWithoutFee) * targetPrice) / FACTOR;
        uint256 preOperationPairTokenBalance = balanceOfToken(pairTokenAddress);

        uint256[] memory amounts;
        if (poolType == PoolType.VELO_LIKE) {
            // For VELO_LIKE pools, use IVRouter for swapping
            IVRouter.Route[] memory routes = new IVRouter.Route[](1);
            routes[0] = IVRouter.Route({
                from: ionAddress,
                to: pairTokenAddress,
                stable: isStablePool,
                factory: factoryAddress
            });
            amounts = IVRouter(routerAddress).swapExactTokensForTokens(
                ionAmount,
                minPairTokenAmountOut,
                routes,
                address(this),
                block.timestamp + 1
            );
        } else {
            // For SOLIDLY_V2 pools, use the Solidly router
            ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](1);
            routes[0] = ISolidlyRouter.route({from: ionAddress, to: pairTokenAddress, stable: isStablePool});
            amounts = ISolidlyRouter(routerAddress).swapExactTokensForTokens(
                ionAmount,
                minPairTokenAmountOut,
                routes,
                address(this),
                block.timestamp + 1
            );
        }
        uint256 pairTokenAmount = amounts[1];

        uint256 postOperationPairTokenBalance = balanceOfToken(pairTokenAddress);
        if (pairTokenAmount != postOperationPairTokenBalance - preOperationPairTokenBalance)
            revert SwapPairTokenAmountOutMismatch(
                pairTokenAmount,
                postOperationPairTokenBalance - preOperationPairTokenBalance
            );
        if (pairTokenAmount < minPairTokenAmountOut)
            revert InsufficientOutputAmount(pairTokenAmount, minPairTokenAmountOut);
        uint256 currentPrice = ionPrice();
        if (currentPrice <= ionPriceLowerBound(targetPrice)) revert PriceNotInRange(currentPrice);
        emit MintSell(ionAmount, pairTokenAmount);
    }

    /// @inheritdoc MasterAMO
    function _addLiquidity(uint256 pairTokenAmount) internal override returns (uint256 liquidity) {
        // Calculate ION amount to mint based on the PairToken amount and multiplier.
        uint256 ionMintAmount = (scalePairTokenToIonDecimals(pairTokenAmount) * ionMultiplayer) / FACTOR;
        IMinter(ionMinterAddress).protocolMint(address(this), ionMintAmount);

        // Approve router for ION and PairToken transfers.
        IERC20(ionAddress).approve(routerAddress, ionMintAmount);
        IERC20(pairTokenAddress).forceApprove(routerAddress, pairTokenAmount);

        uint256 lpBalanceBefore = balanceOfToken(poolAddress);
        // Add liquidity using the Solidly router.
        uint256 ionSpent;
        uint256 pairTokenSpent;
        (ionSpent, pairTokenSpent, liquidity) = ISolidlyRouter(routerAddress).addLiquidity(
            ionAddress,
            pairTokenAddress,
            isStablePool,
            ionMintAmount,
            pairTokenAmount,
            1, // minIonSpend
            1, // minPairTokenSpend
            address(this),
            block.timestamp + 1
        );
        uint256 lpBalanceAfter = balanceOfToken(poolAddress);
        if (liquidity != lpBalanceAfter - lpBalanceBefore)
            revert LpAmountOutMismatch(liquidity, lpBalanceAfter - lpBalanceBefore);

        // Revoke approvals for security.
        IERC20(ionAddress).approve(routerAddress, 0);
        IERC20(pairTokenAddress).forceApprove(routerAddress, 0);

        // Deposit liquidity into the gauge.
        IERC20(poolAddress).approve(gaugeAddress, liquidity);
        if (useTokenId) {
            IGauge(gaugeAddress).deposit(liquidity, tokenId);
        } else {
            IGauge(gaugeAddress).deposit(liquidity);
        }

        // Burn any excessive minted BOOST.
        if (ionMintAmount > ionSpent) IIon(ionAddress).burn(ionMintAmount - ionSpent);
        emit AddLiquidityAndDeposit(ionSpent, pairTokenSpent, liquidity, tokenId);
    }

    ////// UNFARM-BUY-BURN FUNCTIONS //////

    function _calculateLiquidityToUnfarm() internal view returns (uint256 liquidity) {
        (uint256 ionReserve, uint256 pairTokenReserve) = getReserves();
        uint256 totalLp = IERC20(poolAddress).totalSupply();
        uint256 sqrtResRatio = Math.sqrt((FACTOR ** 2 * pairTokenReserve) / ((ionReserve * ionTargetPrice()) / FACTOR));
        uint256 removalPercentage = (FACTOR * (FACTOR - sqrtResRatio)) / (FACTOR - ((poolFee * sqrtResRatio) / FACTOR));
        liquidity = (totalLp * removalPercentage) / FACTOR;
    }

    /// @inheritdoc MasterAMO
    function _unfarmBuyBurn() internal override returns (uint256 liquidity, uint256 postOperationIonPrice) {
        liquidity = _calculateLiquidityToUnfarm();
        liquidity = (liquidity * pairTokenBuyRatio) / FACTOR;

        // Withdraw LP tokens from the gauge.
        IGauge(gaugeAddress).withdraw(liquidity);
        IERC20(poolAddress).approve(routerAddress, liquidity);

        uint256 preOperationPairTokenBalance = balanceOfToken(pairTokenAddress);

        (uint256 ionRemoved, uint256 pairTokenRemoved) = ISolidlyRouter(routerAddress).removeLiquidity(
            ionAddress,
            pairTokenAddress,
            isStablePool,
            liquidity,
            1,
            1,
            address(this),
            block.timestamp + 1
        );
        uint256 targetPrice = ionTargetPrice();
        uint256 postOperationPairTokenBalance = balanceOfToken(pairTokenAddress);
        if (pairTokenRemoved != postOperationPairTokenBalance - preOperationPairTokenBalance)
            revert SwapPairTokenAmountOutMismatch(
                pairTokenRemoved,
                postOperationPairTokenBalance - preOperationPairTokenBalance
            );

        // Approve router for the PairToken swap.
        IERC20(pairTokenAddress).forceApprove(routerAddress, pairTokenRemoved);
        uint256[] memory amounts;
        uint256 pairTokenRemovedAmountWithoutFee = pairTokenRemoved - ((pairTokenRemoved * poolFee) / FACTOR);
        uint256 minIonSwapAmountOut = (scalePairTokenToIonDecimals(pairTokenRemovedAmountWithoutFee) * FACTOR) /
            targetPrice;
        if (poolType == PoolType.VELO_LIKE) {
            IVRouter.Route[] memory routes = new IVRouter.Route[](1);
            routes[0] = IVRouter.Route({
                from: pairTokenAddress,
                to: ionAddress,
                stable: isStablePool,
                factory: factoryAddress
            });
            amounts = IVRouter(routerAddress).swapExactTokensForTokens(
                pairTokenRemoved,
                minIonSwapAmountOut,
                routes,
                address(this),
                block.timestamp + 1
            );
        } else {
            ISolidlyRouter.route[] memory routes = new ISolidlyRouter.route[](1);
            routes[0] = ISolidlyRouter.route(pairTokenAddress, ionAddress, isStablePool);
            amounts = ISolidlyRouter(routerAddress).swapExactTokensForTokens(
                pairTokenRemoved,
                minIonSwapAmountOut,
                routes,
                address(this),
                block.timestamp + 1
            );
        }
        postOperationIonPrice = ionPrice();
        if (postOperationIonPrice >= ionPriceUpperBound(targetPrice)) revert PriceNotInRange(postOperationIonPrice);
        uint256 ionAmountOut = amounts[1];
        IIon(ionAddress).burn(ionRemoved + ionAmountOut);
        emit UnfarmBuyBurn(ionRemoved, pairTokenRemoved, liquidity, ionAmountOut);
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
            IGauge(gaugeAddress).getReward(address(this));
        } else if (passTokens) {
            IGauge(gaugeAddress).getReward(address(this), tokens);
        } else {
            IGauge(gaugeAddress).getReward();
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
    function ionPrice() public view override returns (uint256 price) {
        if (!isStablePool) {
            (uint256 ionReserve, uint256 pairTokenReserve) = getReserves();
            price = (10 ** PRICE_DECIMALS * pairTokenReserve) / ionReserve;
        } else {
            uint256 amountIn = 10 ** ionDecimals;
            amountIn += (amountIn * poolFee) / FACTOR;
            uint256 amountOut = IPair(poolAddress).getAmountOut(amountIn, ionAddress);
            if (pairTokenDecimals > PRICE_DECIMALS) {
                price = amountOut / 10 ** (pairTokenDecimals - PRICE_DECIMALS);
            } else {
                price = amountOut * 10 ** (PRICE_DECIMALS - pairTokenDecimals);
            }
        }
    }

    /// @inheritdoc IV2AMO
    function getReserves() public view override returns (uint256 ionReserve, uint256 pairTokenReserve) {
        (uint256 reserve0, uint256 reserve1, ) = IPair(poolAddress).getReserves();
        if (ionAddress < pairTokenAddress) {
            ionReserve = reserve0;
            pairTokenReserve = scalePairTokenToIonDecimals(reserve1);
        } else {
            ionReserve = reserve1;
            pairTokenReserve = scalePairTokenToIonDecimals(reserve0);
        }
    }
}
