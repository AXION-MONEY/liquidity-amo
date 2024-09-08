// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ILiquidityAMO} from "./interfaces/ILiquidityAMO.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IPublicAMO} from "./interfaces/IPublicAMO.sol";

/// @title A public wrapper for BOOST-USD LiquidityAMO
/// @notice The PublicAMO contract is responsible for maintaining the BOOST-USD peg in Solidly pairs.
/// It achieves this through minting and burning BOOST tokens, as well as adding and removing liquidity from the BOOST-USD pair.
/// @dev This contract implements the IPublicAMO interface and inherits from Initializable, AccessControlEnumerableUpgradeable, and PausableUpgradeable.
contract PublicAMO is IPublicAMO, Initializable, AccessControlEnumerableUpgradeable, PausableUpgradeable {
    ////////////////////////// ROLES //////////////////////////
    bytes32 public constant AMO_SETTER_ROLE = keccak256("AMO_SETTER_ROLE");
    bytes32 public constant RATIO_SETTER_ROLE = keccak256("RATIO_SETTER_ROLE");
    bytes32 public constant COOLDOWN_SETTER_ROLE = keccak256("COOLDOWN_SETTER_ROLE");
    bytes32 public constant LIMIT_SETTER_ROLE = keccak256("LIMIT_SETTER_ROLE");
    bytes32 public constant BOUND_SETTER_ROLE = keccak256("BOUND_SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    ////////////////////////// VARIABLES //////////////////////////
    address public amoAddress;
    uint256 public boostLowerPriceSell;  // Decimals: 6
    uint256 public boostUpperPriceBuy;  // Decimals: 6
    uint256 public boostSellRatio;  // Decimals: 6
    uint256 public usdBuyRatio;  // Decimals: 6
    uint256 public boostLimitToMint;
    uint256 public lpLimitToUnfarm;
    uint256 public cooldownPeriod;
    uint256 public tokenId;
    bool public useToken;
    mapping(address => uint256) public userLastTx;

    ////////////////////////// ERRORS //////////////////////////
    error PriceNotInRange();
    error InvalidBoostAmount();
    error InvalidLpAmount();
    error ZeroAddress();
    error InvalidAmount();
    error CooldownNotFinished();

    ////////////////////////// INITIALIZER //////////////////////////
    /// @inheritdoc IPublicAMO
    function initialize(
        address admin_,
        address amoAddress_
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        if (admin_ == address(0) || amoAddress_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        amoAddress = amoAddress_;
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////

    /// @inheritdoc IPublicAMO
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IPublicAMO
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// PUBLIC FUNCTIONS //////////////////////////
    /// @inheritdoc IPublicAMO
    function mintSell() external whenNotPaused
    returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 dryPowderAmount) {
        // Checks cooldown time
        if(userLastTx[msg.sender] + cooldownPeriod > block.timestamp) revert CooldownNotFinished();
        userLastTx[msg.sender] = block.timestamp;

        address lpAddress = ILiquidityAMO(amoAddress).usd_boost();
        address boostAddress = ILiquidityAMO(amoAddress).boost();
        uint8 boostDecimals = IERC20(boostAddress).decimals();
        // TODO: check the reserves
        uint256 boostBalance = IERC20(boostAddress).balanceOf(lpAddress);
        address usdAddress = ILiquidityAMO(amoAddress).usd();
        uint8 usdDecimals = IERC20(usdAddress).decimals();
        uint256 usdBalance = IERC20(usdAddress).balanceOf(lpAddress);
        boostAmountIn = (
            (
                (
                    (boostBalance + (usdBalance * 10 ** (boostDecimals - usdDecimals))) / 2
                ) - boostBalance
            ) * boostSellRatio
        ) / 10 ** 6;
        if (
            boostAmountIn > boostLimitToMint || // Set a high limit on boost amount to be minted, sold and farmed
            boostBalance < (usdBalance * 10 ** (boostDecimals - usdDecimals)) // Checks if the expected boost price is more than 1$
        ) revert InvalidBoostAmount();

        (usdAmountOut, dryPowderAmount) = ILiquidityAMO(amoAddress).mintAndSellBoost(
            boostAmountIn,
            boostAmountIn / (10 ** (boostDecimals - usdDecimals)), //minUsdAmountOut
            block.timestamp  //deadline
        );

        uint256 boostPrice = (usdAmountOut * 10 ** (boostDecimals + 6 - usdDecimals)) / boostAmountIn;

        // Checks if the actual average price of boost when selling is greater than the boostLowerPriceSell
        if (boostPrice < boostLowerPriceSell) revert PriceNotInRange();

        emit MintSellExecuted(boostAmountIn, usdAmountOut);
    }

    /// @inheritdoc IPublicAMO
    function unfarmBuyBurn() external whenNotPaused
    returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut) {
        address lpAddress = ILiquidityAMO(amoAddress).usd_boost();
        address boostAddress = ILiquidityAMO(amoAddress).boost();
        uint8 boostDecimals = IERC20(boostAddress).decimals();
        // TODO: check the reserves
        uint256 boostBalance = IERC20(boostAddress).balanceOf(lpAddress);
        address usdAddress = ILiquidityAMO(amoAddress).usd();
        uint8 usdDecimals = IERC20(usdAddress).decimals();
        uint256 usdBalance = IERC20(usdAddress).balanceOf(lpAddress);
        uint256 totalLP = IERC20(lpAddress).totalSupply();   //  is the total amounts of LP in the contract
        uint256 usdNeeded = (
            (
                (
                    ((boostBalance / 10 ** (boostDecimals - usdDecimals)) + usdBalance) / 2
                ) - usdBalance
            ) * usdBuyRatio
        ) / 10 ** 6;
        uint256 lpAmount = (usdNeeded * totalLP) / usdBalance;
        lpAmount = (lpAmount * (1 - (lpAmount / totalLP)));

        // Checks cooldown time
        if(userLastTx[msg.sender] + cooldownPeriod > block.timestamp) revert CooldownNotFinished();
        userLastTx[msg.sender] = block.timestamp;

        // Set a high limit on LP amount to be unfarmed, bought and burned
        if (lpAmount > lpLimitToUnfarm) revert InvalidLpAmount();

        (boostRemoved, usdRemoved, boostAmountOut) = ILiquidityAMO(amoAddress).unfarmBuyBurn(
            lpAmount,
            (lpAmount * boostBalance) / IERC20(lpAddress).totalSupply(), // minBoostRemove
            usdNeeded, // minUsdRemove
            usdNeeded * (10 ** (boostDecimals - usdDecimals)), //minBoostAmountOut
            block.timestamp  //deadline
        );

        uint256 boostPrice = (usdRemoved * 10 ** (boostDecimals + 6 - usdDecimals)) / (boostAmountOut);

        // Checks if the actual average price of boost when buying is less than the boostUpperPriceBuy
        if (boostPrice > boostUpperPriceBuy) revert PriceNotInRange();

        emit UnfarmBuyBurnExecuted(lpAmount, boostRemoved, usdRemoved);
    }

    ////////////////////////// SETTER FUNCTIONS //////////////////////////
    /// @inheritdoc IPublicAMO
    function setLimits(
        uint256 boostLimitToMint_,
        uint256 lpLimitToUnfarm_
    ) external onlyRole(LIMIT_SETTER_ROLE) {
        boostLimitToMint = boostLimitToMint_;
        lpLimitToUnfarm = lpLimitToUnfarm_;
        emit LimitsSet(boostLimitToMint_, lpLimitToUnfarm_);
    }

    /// @inheritdoc IPublicAMO
    function setBuyAndSellBound(
        uint256 boostUpperPriceBuy_,
        uint256 boostLowerPriceSell_
    ) external onlyRole(BOUND_SETTER_ROLE) {
        boostUpperPriceBuy = boostUpperPriceBuy_;
        boostLowerPriceSell = boostLowerPriceSell_;
        emit BuyAndSellBoundSet(boostUpperPriceBuy_, boostLowerPriceSell_);
    }

    /// @inheritdoc IPublicAMO
    function setAmo(
        address amoAddress_
    ) external onlyRole(AMO_SETTER_ROLE) {
        if (amoAddress_ == address(0)) revert ZeroAddress();
        amoAddress = amoAddress_;
        emit AMOSet(amoAddress_);
    }

    /// @inheritdoc IPublicAMO
    function setCooldownPeriod(
        uint256 cooldownPeriod_
    ) external onlyRole(COOLDOWN_SETTER_ROLE) {
        cooldownPeriod = cooldownPeriod_;
        emit CooldownPeriodSet(cooldownPeriod_);
    }

    /// @inheritdoc IPublicAMO
    function setToken(
        uint256 tokenId_,
        bool useToken_
    ) external onlyRole(COOLDOWN_SETTER_ROLE) {
        tokenId = tokenId_;
        useToken = useToken_;
        emit TokenSet(tokenId_, useToken_);
    }

    /// @inheritdoc IPublicAMO
    function setBoostSellRatio(
        uint256 boostSellRatio_
    ) external onlyRole(RATIO_SETTER_ROLE) {
        boostSellRatio = boostSellRatio_;
        emit BoostSellRatioSet(boostSellRatio_);
    }

    /// @inheritdoc IPublicAMO
    function setUsdBuyRatio(
        uint256 usdBuyRatio_
    ) external onlyRole(RATIO_SETTER_ROLE) {
        usdBuyRatio = usdBuyRatio_;
        emit UsdBuyRatioSet(usdBuyRatio_);
    }
}