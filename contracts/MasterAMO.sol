// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMinter} from "./interfaces/IMinter.sol";
import {IMasterAMO} from "./interfaces/IMasterAMO.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPriceManager} from "./price-manager/interfaces/IPriceManager.sol";
import {IIon} from "./interfaces/IIon.sol";

/**
 * @title MasterAMO Contract
 * @notice This abstract contract provides a framework for Automated Market Operations (AMO)
 *         within the ION stablecoin ecosystem. It facilitates operations such as minting ION,
 *         selling it for PairToken, adding liquidity to a ION-PairToken pool, and executing liquidity removal,
 *         buying, and burning when necessary to maintain the peg.
 *
 * @dev The contract is designed to be upgradeable via a timelock mechanism to allow future enhancements.
 *      It is pausable, and only authorized roles may execute certain operations:
 *      - DEFAULT_ADMIN_ROLE: Admin privileges.
 *      - SETTER_ROLE: For setting critical parameters.
 *      - PAUSER_ROLE / UNPAUSER_ROLE: For pausing and unpausing contract operations.
 *      - WITHDRAWER_ROLE: For token withdrawals.
 *      - OPERATOR_ROLE: Bypass swap ratio limit.
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
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

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
    /// @inheritdoc IMasterAMO
    bytes32 public constant override OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // -------------------------------------------------------------
    //                        STATE VARIABLES
    // -------------------------------------------------------------

    ////// IMMUTABLE //////
    /// @inheritdoc IMasterAMO
    address public override ionAddress;
    /// @inheritdoc IMasterAMO
    address public override pairTokenAddress;
    /// @inheritdoc IMasterAMO
    address public override poolAddress;
    /// @inheritdoc IMasterAMO
    uint8 public override ionDecimals;
    /// @inheritdoc IMasterAMO
    uint8 public override pairTokenDecimals;
    /// @inheritdoc IMasterAMO
    address public override ionMinterAddress;
    /// @inheritdoc IMasterAMO
    address public priceManagerContractAddress;
    /// @inheritdoc IMasterAMO
    IPriceManager.TokenType public pairTokenType;

    ////// MUTABLE //////
    /// @inheritdoc IMasterAMO
    uint24 public override validRangeWidth;
    /// @inheritdoc IMasterAMO
    uint256 public override ionTargetPricePremium;
    /// @inheritdoc IMasterAMO
    uint24 public override sellRatio;
    /// @inheritdoc IMasterAMO
    uint24 public override buyRatio;

    struct LiquidityAtPeriod {
        uint256 periodIndex;
        uint256 addedAmount;
        uint256 removedAmount;
    }
    LiquidityAtPeriod public lastLiquidityAmounts;
    uint256 public periodDuration;
    uint24 public addLiquidityRatioLimit;
    uint24 public removeLiquidityRatioLimit;

    // -------------------------------------------------------------
    //                      INTERNAL CONSTANTS
    // -------------------------------------------------------------
    // @notice ION price decimals
    uint8 internal constant PRICE_DECIMALS = 6;
    // @notice Decimals for parameter calculations.
    uint8 internal constant PARAMS_DECIMALS = 6;
    // @notice One (1) scaled with the internal decimal convention.
    uint256 internal constant SCALED_UNIT = 10 ** PARAMS_DECIMALS;

    // -------------------------------------------------------------
    //                           MODIFIERS
    // -------------------------------------------------------------
    /// @dev Modifier to validate mintSellFarm.
    modifier validateSell() {
        _validateSell();
        _;
    }

    /// @dev Modifier to validate unfarmBuyBurn.
    modifier validateBuy() {
        _validateBuy();
        _;
    }

    // -------------------------------------------------------------
    //                        INITIALIZATION
    // -------------------------------------------------------------
    /**
     * @notice Initializes the MasterAMO contract.
     * @param admin Address to be granted the DEFAULT_ADMIN_ROLE.
     * @param ionAddress_ Address of the Ion stableCoin.
     * @param pairTokenAddress_ Address of the pairToken.
     * @param pool_ Address of the liquidity pool for the ION-PairToken pair.
     * @param ionMinterAddress_ Address of the Ion minter contract.
     * @param priceManager_ Address of the price manager contract.
     * @param pairTokenType_ The type of the token paired with ION.
     * @param validRangeWidth_ The valid range width for liquidity addition.
     * @param sellRatio_ The sell ratio as mintSellFarm's swap ratio.
     * @param buyRatio_ The buy ratio as unfarmBuyBurn's swap ratio.
     */
    function initialize(
        address admin,
        address ionAddress_,
        address pairTokenAddress_,
        address pool_,
        address ionMinterAddress_,
        address priceManager_,
        IPriceManager.TokenType pairTokenType_,
        uint24 validRangeWidth_,
        uint24 sellRatio_,
        uint24 buyRatio_
    ) internal onlyInitializing {
        __AccessControlEnumerable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        if (
            admin == address(0) ||
            ionAddress_ == address(0) ||
            pairTokenAddress_ == address(0) ||
            pool_ == address(0) ||
            ionMinterAddress_ == address(0)
        ) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        ionAddress = ionAddress_;
        pairTokenAddress = pairTokenAddress_;
        poolAddress = pool_;
        ionDecimals = IERC20Metadata(ionAddress).decimals();
        pairTokenDecimals = IERC20Metadata(pairTokenAddress).decimals();
        ionMinterAddress = ionMinterAddress_;
        priceManagerContractAddress = priceManager_;
        pairTokenType = pairTokenType_;
        ionTargetPricePremium = 0; // Default value.

        // Temporarily grant SETTER_ROLE to msg.sender for initialization
        _grantRole(SETTER_ROLE, msg.sender);
        setParams(validRangeWidth_, sellRatio_, buyRatio_);
        _revokeRole(SETTER_ROLE, msg.sender);
    }

    // -------------------------------------------------------------
    //                        SETTER ACTIONS
    // -------------------------------------------------------------
    /// @inheritdoc IMasterAMO
    function setIonTargetPricePremium(uint256 targetPricePremium_) external onlyRole(SETTER_ROLE) {
        ionTargetPricePremium = targetPricePremium_;
        emit IonTargetPricePremiumSet(ionTargetPricePremium);
    }

    /// @inheritdoc IMasterAMO
    function setParams(
        uint24 validRangeWidth_,
        uint24 sellRatio_,
        uint24 buyRatio_
    ) public override onlyRole(SETTER_ROLE) {
        if (validRangeWidth_ > SCALED_UNIT || sellRatio_ > SCALED_UNIT || buyRatio_ > SCALED_UNIT)
            revert InvalidRatioValue();
        validRangeWidth = validRangeWidth_;
        sellRatio = sellRatio_;
        buyRatio = buyRatio_;
        emit ParamsSet(validRangeWidth, sellRatio, buyRatio);
    }

    function setPeriodDuration(uint256 periodDuration_) public onlyRole(SETTER_ROLE) {
        periodDuration = periodDuration_;
        delete lastLiquidityAmounts;
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
    function currentPeriodIndex() internal view returns (uint256) {
        return block.timestamp / periodDuration;
    }

    function increaseAddedLiquidity(uint256 amount) internal {
        uint256 _currentPeriodIndex = currentPeriodIndex();
        if (lastLiquidityAmounts.periodIndex == _currentPeriodIndex) {
            lastLiquidityAmounts.addedAmount += amount;
        } else {
            lastLiquidityAmounts.addedAmount = amount;
            lastLiquidityAmounts.removedAmount = 0;
            lastLiquidityAmounts.periodIndex = _currentPeriodIndex;
        }
    }

    function increaseRemovedLiquidity(uint256 amount) internal {
        uint256 _currentPeriodIndex = currentPeriodIndex();
        if (lastLiquidityAmounts.periodIndex == _currentPeriodIndex) {
            lastLiquidityAmounts.removedAmount += amount;
        } else {
            lastLiquidityAmounts.addedAmount = 0;
            lastLiquidityAmounts.removedAmount = amount;
            lastLiquidityAmounts.periodIndex = _currentPeriodIndex;
        }
    }

    function decreaseAddedLiquidity(uint256 amount) internal {
        assert(lastLiquidityAmounts.periodIndex == currentPeriodIndex());
        lastLiquidityAmounts.addedAmount -= amount;
    }

    function decreaseRemovedLiquidity(uint256 amount) internal {
        assert(lastLiquidityAmounts.periodIndex == currentPeriodIndex());
        lastLiquidityAmounts.removedAmount -= amount;
    }

    function periodRemainingLiquidityForRemoving(uint256 currentLiquidity) internal view returns (uint256) {
        uint256 addedAmount;
        uint256 removedAmount;
        if (lastLiquidityAmounts.periodIndex == currentPeriodIndex()) {
            addedAmount = lastLiquidityAmounts.addedAmount;
            removedAmount = lastLiquidityAmounts.removedAmount;
        }
        uint256 periodTotalLiquidity = currentLiquidity + removedAmount - addedAmount;
        uint256 totalAllowed = periodTotalLiquidity.mulDiv(removeLiquidityRatioLimit, SCALED_UNIT);
        if (totalAllowed <= removedAmount) revert NoRemainingLiquidity();
        return totalAllowed - removedAmount;
    }

    function periodRemainingLiquidityForAdding(uint256 currentLiquidity) internal view returns (uint256) {
        uint256 addedAmount;
        uint256 removedAmount;
        if (lastLiquidityAmounts.periodIndex == currentPeriodIndex()) {
            addedAmount = lastLiquidityAmounts.addedAmount;
            removedAmount = lastLiquidityAmounts.removedAmount;
        }
        uint256 periodTotalLiquidity = currentLiquidity + removedAmount - addedAmount;
        uint256 totalAllowed = periodTotalLiquidity.mulDiv(addLiquidityRatioLimit, SCALED_UNIT);
        if (totalAllowed <= addedAmount) revert NoRemainingLiquidity();
        return totalAllowed - addedAmount;
    }

    /**
     * @notice Sorts two token amounts based on token addresses.
     * @param ionAmount The Ion token amount.
     * @param pairAmount The pair token amount.
     * @return (uint256, uint256) The sorted token amounts.
     */
    function orderAmountsByTokenAddress(
        uint256 ionAmount,
        uint256 pairAmount
    ) internal view returns (uint256, uint256) {
        return (ionAddress < pairTokenAddress) ? (ionAmount, pairAmount) : (pairAmount, ionAmount);
    }

    /**
     * @notice Sorts two signed token amounts based on token addresses.
     * @param amountToken0 The first token amount.
     * @param amountToken1 The second token amount.
     * @return (int256, int256) The sorted token amounts.
     */
    function orderAmountsByTokenAddress(
        int256 amountToken0,
        int256 amountToken1
    ) internal view returns (int256, int256) {
        return (ionAddress < pairTokenAddress) ? (amountToken0, amountToken1) : (amountToken1, amountToken0);
    }

    /**
     * @notice Scales PairToken amount to match ION decimal precision.
     * @dev Adjusts the decimal places of the input PairToken amount to align with ION token's decimal precision.
     * @dev This function assumes that ION has more decimal places than PairToken.
     * @param pairTokenAmount The amount in pairToken, using pairToken's decimal precision.
     * @return uint256 The equivalent amount in ION's decimal precision.
     */
    function scalePairTokenToIonDecimals(uint256 pairTokenAmount) internal view returns (uint256) {
        return pairTokenAmount * 10 ** (ionDecimals - pairTokenDecimals);
    }

    /**
     * @notice Scales an ION amount to match pairToken decimal precision.
     * @dev Adjusts the decimal places of the input ION amount to align with pairToken's decimal precision.
     * @dev This function assumes that ION has more decimal places than PairToken.
     * @param ionAmount The amount in ION, using ION's decimal precision.
     * @return uint256 The equivalent amount in PairToken's decimal precision.
     */
    function scaleIonToPairTokenDecimals(uint256 ionAmount) internal view returns (uint256) {
        return ionAmount / 10 ** (ionDecimals - pairTokenDecimals);
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
    function ionPriceLowerBound(uint256 price) internal view returns (uint256) {
        return price - price.mulDiv(validRangeWidth, SCALED_UNIT);
    }

    /**
     * @notice Calculates the upper price bound based on the valid range.
     * @param price Current price.
     * @return The upper bound price.
     */
    function ionPriceUpperBound(uint256 price) internal view returns (uint256) {
        return price + price.mulDiv(validRangeWidth, SCALED_UNIT);
    }

    /// @notice Internal function to validate mintSellFarm.
    function _validateSell() internal view virtual {
        uint256 currentPrice = ionPriceInPairToken();
        uint256 targetPrice = ionTargetPriceInPairToken();
        if (currentPrice <= ionPriceUpperBound(targetPrice)) revert PriceAlreadyInRange(currentPrice, targetPrice);
    }

    /// @notice Internal function to validate unfarmBuyBurn.
    function _validateBuy() internal view virtual {
        uint256 currentPrice = ionPriceInPairToken();
        uint256 targetPrice = ionTargetPriceInPairToken();
        if (currentPrice >= ionPriceLowerBound(targetPrice)) revert PriceAlreadyInRange(currentPrice, targetPrice);
    }

    // -------------------------------------------------------------
    //                   INTERNAL FUNCTIONS
    // -------------------------------------------------------------

    ////// MINT-SELL-FARM FUNCTIONS //////

    /**
     * @notice Internal function to mint ION and sell it for pairToken.
     * @param swapRatio The swap ratio for selling ION.
     * @return postOperationIonPrice The new average ION price after the operation.
     * @dev Must be implemented by a derived contract.
     */
    function _mintAndSell(uint24 swapRatio) internal virtual returns (uint256 postOperationIonPrice);

    /**
     * @notice Internal function to add liquidity to the pool.
     * @param pairTokenAmount The pairToken amount to add.
     * @return liquidity Liquidity tokens received.
     * @dev Must be implemented by a derived contract.
     */
    function _addLiquidity(uint256 pairTokenAmount) internal virtual returns (uint256 liquidity);

    /**
     * @notice Internal function to perform mint, sell and liquidity addition when ION is over peg.
     * @param swapRatio The swap ratio for selling ION.
     * @return liquidity Liquidity tokens received.
     * @return postOperationIonPrice The new average ION price after the operation.
     * @dev Must be implemented by a derived contract.
     * @dev Has been Used for public functions
     */
    function _mintSellFarm(uint24 swapRatio) internal returns (uint256 liquidity, uint256 postOperationIonPrice) {
        postOperationIonPrice = _mintAndSell(swapRatio);
        uint256 targetPrice = ionTargetPriceInPairToken();
        if (
            postOperationIonPrice > ionPriceLowerBound(targetPrice) &&
            postOperationIonPrice < ionPriceUpperBound(targetPrice)
        ) {
            uint256 pairTokenBalance = IERC20(pairTokenAddress).balanceOf(address(this));
            liquidity = _addLiquidity(pairTokenBalance);
        }
    }

    ////// UNFARM-BUY-BURN FUNCTIONS //////

    /**
     * @notice Internal function to remove liquidity from the pool.
     * @param liquidity The liquidity amount to remove.
     * @return ionRemoved The ION amount removed.
     * @return pairTokenRemoved The PairToken amount removed.
     * @return ionCollectedFee The ION amount part of the collected fee.
     * @return pairTokenCollectedFee The PairToken amount part of the collected fee.
     * @dev Must be implemented by a derived contract.
     */
    function _removeLiquidity(
        uint256 liquidity
    )
        internal
        virtual
        returns (uint256 ionRemoved, uint256 pairTokenRemoved, uint256 ionCollectedFee, uint256 pairTokenCollectedFee);

    /**
     * @notice Internal function to perform un-farming, buying, and burning when ION is under peg.
     * @param swapRatio The swap ratio for buying ION.
     * @return liquidity Liquidity tokens affected.
     * @return postOperationIonPrice The new average ION price after the operation.
     * @dev Must be implemented by a derived contract.
     */
    function _unfarmBuyBurn(
        uint24 swapRatio
    ) internal virtual returns (uint256 liquidity, uint256 postOperationIonPrice);

    // -------------------------------------------------------------
    //                      EXTERNAL FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IMasterAMO
    function addLiquidity() external override whenNotPaused nonReentrant returns (uint256 liquidity) {
        // Only add liquidity when current Ion price is within the valid range.
        uint256 currentPrice = ionPriceInPairToken();
        uint256 targetPrice = ionTargetPriceInPairToken();
        if (currentPrice <= ionPriceLowerBound(targetPrice) || currentPrice >= ionPriceUpperBound(targetPrice))
            revert InvalidRatioToAddLiquidity();

        uint256 pairTokenBalance = IERC20(pairTokenAddress).balanceOf(address(this));
        liquidity = _addLiquidity(pairTokenBalance);
    }

    /// @inheritdoc IMasterAMO
    function removeLiquidity(
        uint256 liquidity,
        uint256 ionMinRemove,
        uint256 pairTokenMinRemove,
        address recipient
    )
        external
        override
        onlyRole(WITHDRAWER_ROLE)
        returns (uint256 ionRemoved, uint256 pairTokenRemoved, uint256 ionCollectedFee, uint256 pairTokenCollectedFee)
    {
        if (recipient == address(0)) revert ZeroAddress();
        (ionRemoved, pairTokenRemoved, ionCollectedFee, pairTokenCollectedFee) = _removeLiquidity(liquidity);
        if (ionRemoved < ionMinRemove) revert InsufficientOutputAmount(ionRemoved, ionMinRemove);
        if (pairTokenRemoved < pairTokenMinRemove)
            revert InsufficientOutputAmount(pairTokenRemoved, pairTokenMinRemove);
        IERC20(pairTokenAddress).safeTransfer(recipient, pairTokenRemoved + pairTokenCollectedFee);
        IIon(ionAddress).burn(ionRemoved + ionCollectedFee);
    }

    /// @inheritdoc IMasterAMO
    function mintSellFarm()
        external
        override
        whenNotPaused
        nonReentrant
        validateSell
        returns (uint256 liquidity, uint256 postOperationIonPrice)
    {
        uint24 swapRatio = hasRole(OPERATOR_ROLE, msg.sender) ? uint24(SCALED_UNIT) : sellRatio;
        (liquidity, postOperationIonPrice) = _mintSellFarm(swapRatio);
    }

    /// @inheritdoc IMasterAMO
    function unfarmBuyBurn()
        external
        override
        whenNotPaused
        nonReentrant
        validateBuy
        returns (uint256 liquidity, uint256 postOperationIonPrice)
    {
        uint24 swapRatio = hasRole(OPERATOR_ROLE, msg.sender) ? uint24(SCALED_UNIT) : buyRatio;
        (liquidity, postOperationIonPrice) = _unfarmBuyBurn(swapRatio);
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
    function ionPriceInPairToken() public view virtual override returns (uint256 price);

    /// @inheritdoc IMasterAMO
    function ionTargetPriceInPairToken() public view override returns (uint256) {
        uint256 pairTokenPrice;
        if (pairTokenType == IPriceManager.TokenType.STABLE) {
            pairTokenPrice = IPriceManager(priceManagerContractAddress).stableTokenPrice(pairTokenAddress);
        } else {
            pairTokenPrice = IPriceManager(priceManagerContractAddress).stakedTokenPrice(pairTokenType);
        }
        return Math.mulDiv(SCALED_UNIT, SCALED_UNIT, pairTokenPrice) + ionTargetPricePremium;
    }
}
