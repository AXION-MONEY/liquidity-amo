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
import {IMasterAMO} from "./interfaces/IMasterAMO.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPriceManager} from "./price-manager/interfaces/IPriceManager.sol";

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
    PairTokenType public pairTokenType;

    ////// MUTABLE //////
    /// @inheritdoc IMasterAMO
    uint256 public override ionMultiplayer;
    /// @inheritdoc IMasterAMO
    uint24 public override validRangeWidth;
    /// @inheritdoc IMasterAMO
    uint256 public override ionTargetPricePremium;

    // -------------------------------------------------------------
    //                      INTERNAL CONSTANTS
    // -------------------------------------------------------------
    // @notice ION price decimals
    uint8 internal constant PRICE_DECIMALS = 6;
    // @notice Decimals for parameter calculations.
    uint8 internal constant PARAMS_DECIMALS = 6;
    // @notice Scaling factor.
    uint256 internal constant FACTOR = 10 ** PARAMS_DECIMALS;
    // @notice Indicates a ION → PairToken swap.
    bool internal constant SELL_ION = true;
    // @notice Indicates a PairToken → ION swap.
    bool internal constant BUY_ION = false;

    // -------------------------------------------------------------
    //                           MODIFIERS
    // -------------------------------------------------------------
    /**
     * @dev Modifier to validate swap parameters.
     * @param ionForPairToken A boolean indicating the swap direction: true for Ion → PairToken,
     *        false for PairToken → Ion.
     */
    modifier validateSwap(bool ionForPairToken) {
        _validateSwap(ionForPairToken);
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
     */
    function initialize(
        address admin,
        address ionAddress_,
        address pairTokenAddress_,
        address pool_,
        address ionMinterAddress_,
        address priceManager_,
        PairTokenType pairTokenType_
    ) public onlyInitializing {
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
    }

    // -------------------------------------------------------------
    //                        SETTER ACTIONS
    // -------------------------------------------------------------
    /**
     * @notice Sets the premium offset used in target price calculations.
     * @param _targetPricePremium The new premium offset.
     */
    function setIonTargetPricePremium(uint256 _targetPricePremium) external onlyRole(SETTER_ROLE) {
        ionTargetPricePremium = _targetPricePremium;
        emit SetIonTargetPricePremium(ionTargetPricePremium);
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
        return price - ((price * validRangeWidth) / FACTOR);
    }

    /**
     * @notice Calculates the upper price bound based on the valid range.
     * @param price Current price.
     * @return The upper bound price.
     */
    function ionPriceUpperBound(uint256 price) internal view returns (uint256) {
        return price + ((price * validRangeWidth) / FACTOR);
    }

    /**
     * @notice Internal function to validate swap parameters.
     * @param ionForPairToken Swap direction: true for ION → pairToken, false for pairToken → ION.
     */
    function _validateSwap(bool ionForPairToken) internal view virtual;

    // -------------------------------------------------------------
    //                   INTERNAL FUNCTIONS
    // -------------------------------------------------------------

    ////// MINT-SELL-FARM FUNCTIONS //////

    /**
     * @notice Internal function to mint ION and sell it for pairToken.
     * @dev Must be implemented by a derived contract.
     */
    function _mintAndSell() internal virtual;

    /**
     * @notice Internal function to add liquidity to the pool.
     * @param pairTokenAmount The pairToken amount to add.
     * @return liquidity Liquidity tokens received.
     * @dev Must be implemented by a derived contract.
     */
    function _addLiquidity(uint256 pairTokenAmount) internal virtual returns (uint256 liquidity);

    /**
     * @notice Internal function to perform mint, sell and liquidity addition when ION is over peg.
     * @return liquidity Liquidity tokens received.
     * @return postOperationIonPrice The new average ION price after the operation.
     * @dev Must be implemented by a derived contract.
     * @dev Has been Used for public functions
     */
    function _mintSellFarm() internal returns (uint256 liquidity, uint256 postOperationIonPrice) {
        _mintAndSell();
        postOperationIonPrice = ionPrice();
        uint256 targetPrice = ionTargetPrice();
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
     * @notice Internal function to perform un-farming, buying, and burning when ION is under peg.
     * @return liquidity Liquidity tokens affected.
     * @return postOperationIonPrice The new average ION price after the operation.
     * @dev Must be implemented by a derived contract.
     */
    function _unfarmBuyBurn() internal virtual returns (uint256 liquidity, uint256 postOperationIonPrice);

    // -------------------------------------------------------------
    //                      EXTERNAL FUNCTIONS
    // -------------------------------------------------------------

    /// @inheritdoc IMasterAMO
    function addLiquidity() external override whenNotPaused nonReentrant returns (uint256 liquidity) {
        // Only add liquidity when current Ion price is within the valid range.
        uint256 currentPrice = ionPrice();
        uint256 targetPrice = ionTargetPrice();
        if (currentPrice <= ionPriceLowerBound(targetPrice) || currentPrice >= ionPriceUpperBound(targetPrice))
            revert InvalidRatioToAddLiquidity();

        uint256 pairTokenBalance = IERC20(pairTokenAddress).balanceOf(address(this));
        liquidity = _addLiquidity(pairTokenBalance);
    }

    /// @inheritdoc IMasterAMO
    function mintSellFarm()
        external
        override
        whenNotPaused
        nonReentrant
        validateSwap(SELL_ION)
        returns (uint256 liquidity, uint256 postOperationIonPrice)
    {
        (liquidity, postOperationIonPrice) = _mintSellFarm();
    }

    /// @inheritdoc IMasterAMO
    function unfarmBuyBurn()
        external
        override
        whenNotPaused
        nonReentrant
        validateSwap(BUY_ION)
        returns (uint256 liquidity, uint256 postOperationIonPrice)
    {
        (liquidity, postOperationIonPrice) = _unfarmBuyBurn();
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
    function ionPrice() public view virtual override returns (uint256 price);

    /// @inheritdoc IMasterAMO
    function ionTargetPrice() public view override returns (uint256 targetPrice) {
        uint256 baseUnit = 10 ** PRICE_DECIMALS;
        if (pairTokenType == PairTokenType.STABLE) return baseUnit;
        else if (pairTokenType == PairTokenType.SUSDE)
            return IPriceManager(priceManagerContractAddress).sUsdePreviewDeposit(baseUnit) + ionTargetPricePremium;
        else if (pairTokenType == PairTokenType.SFRAX)
            return IPriceManager(priceManagerContractAddress).sFraxPreviewDeposit(baseUnit) + ionTargetPricePremium;
        else if (pairTokenType == PairTokenType.SDAI)
            return IPriceManager(priceManagerContractAddress).sDaiPreviewDeposit(baseUnit) + ionTargetPricePremium;
        else revert InvalidPairTokenType();
    }
}
