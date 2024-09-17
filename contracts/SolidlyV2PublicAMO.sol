// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {ISolidlyV2LiquidityAMO} from "./interfaces/v2/ISolidlyV2LiquidityAMO.sol";
import {ISolidlyV2PublicAMO} from "./interfaces/v2/ISolidlyV2PublicAMO.sol";
import {IPair} from "./interfaces/v2/IPair.sol";

/// @title A public wrapper for BOOST-USD LiquidityAMO
/// @notice The PublicAMO contract is responsible for maintaining the BOOST-USD peg in Solidly pairs.
/// It achieves this through minting and burning BOOST tokens, as well as adding and removing liquidity from the BOOST-USD pair.
/// @dev This contract implements the ISolidlyV2PublicAMO interface and inherits from Initializable, AccessControlEnumerableUpgradeable, and PausableUpgradeable.
contract SolidlyV2PublicAMO is
    ISolidlyV2PublicAMO,
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    ////////////////////////// ROLES //////////////////////////
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    ////////////////////////// VARIABLES //////////////////////////
    address public amoAddress;
    uint256 public boostLowerPriceSell; // Decimals: 6
    uint256 public boostUpperPriceBuy; // Decimals: 6
    uint256 public boostSellRatio; // Decimals: 6
    uint256 public usdBuyRatio; // Decimals: 6
    uint256 public tokenId;
    bool public useToken;

    ////////////////////////// CONSTANTS //////////////////////////
    uint8 private constant DECIMALS = 6;
    uint256 private constant FACTOR = 10 ** DECIMALS;

    ////////////////////////// ERRORS //////////////////////////
    error PriceNotInRange(uint256 price);
    error InvalidReserveRatio(uint256 ratio);
    error InvalidBoostAmount(uint256 amount);
    error InvalidLpAmount(uint256 amount);
    error ZeroAddress();
    error InvalidAmount();

    ////////////////////////// INITIALIZER //////////////////////////
    /// @inheritdoc ISolidlyV2PublicAMO
    function initialize(address admin_, address amoAddress_) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        if (admin_ == address(0) || amoAddress_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        amoAddress = amoAddress_;
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////

    /// @inheritdoc ISolidlyV2PublicAMO
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc ISolidlyV2PublicAMO
    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// PUBLIC FUNCTIONS //////////////////////////
    /// @inheritdoc ISolidlyV2PublicAMO
    function mintSellFarm()
        external
        whenNotPaused
        nonReentrant
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 lpAmount, uint256 newBoostPrice)
    {
        address pool = ISolidlyV2LiquidityAMO(amoAddress).pool();
        address boost = ISolidlyV2LiquidityAMO(amoAddress).boost();
        uint8 boostDecimals = IERC20Metadata(boost).decimals();
        address usd = ISolidlyV2LiquidityAMO(amoAddress).usd();
        uint8 usdDecimals = IERC20Metadata(usd).decimals();
        (uint256 reserve0, uint256 reserve1, ) = IPair(pool).getReserves();
        uint256 boostReserve;
        uint256 usdReserve;
        if (boost < usd) {
            boostReserve = reserve0;
            usdReserve = reserve1 * 10 ** (boostDecimals - usdDecimals); // scaled
        } else {
            boostReserve = reserve1;
            usdReserve = reserve0 * 10 ** (boostDecimals - usdDecimals); // scaled
        }
        // Checks if the expected boost price is more than 1$
        if (usdReserve <= boostReserve) revert InvalidReserveRatio({ratio: (FACTOR * usdReserve) / boostReserve});

        boostAmountIn = (((usdReserve - boostReserve) / 2) * boostSellRatio) / FACTOR;

        (usdAmountOut, , , , lpAmount) = ISolidlyV2LiquidityAMO(amoAddress).mintSellFarm(
            boostAmountIn,
            boostAmountIn / (10 ** (boostDecimals - usdDecimals)), //minUsdAmountOut
            tokenId,
            useToken,
            1, // minUsdSpend
            1, // minLpAmount
            block.timestamp + 1 // deadline
        );

        newBoostPrice = ISolidlyV2LiquidityAMO(amoAddress).boostPrice();

        // Checks if the price of boost is greater than the boostLowerPriceSell
        if (newBoostPrice < boostLowerPriceSell) revert PriceNotInRange(newBoostPrice);

        emit MintSellFarmExecuted(boostAmountIn, usdAmountOut, lpAmount, newBoostPrice);
    }

    /// @inheritdoc ISolidlyV2PublicAMO
    function unfarmBuyBurn()
        external
        whenNotPaused
        nonReentrant
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 boostAmountOut, uint256 newBoostPrice)
    {
        address pool = ISolidlyV2LiquidityAMO(amoAddress).pool();
        address boost = ISolidlyV2LiquidityAMO(amoAddress).boost();
        uint8 boostDecimals = IERC20Metadata(boost).decimals();
        address usd = ISolidlyV2LiquidityAMO(amoAddress).usd();
        uint8 usdDecimals = IERC20Metadata(usd).decimals();
        (uint256 reserve0, uint256 reserve1, ) = IPair(pool).getReserves();
        uint256 boostReserve;
        uint256 usdReserve;
        if (boost < usd) {
            boostReserve = reserve0;
            usdReserve = reserve1 * 10 ** (boostDecimals - usdDecimals); // scaled
        } else {
            boostReserve = reserve1;
            usdReserve = reserve0 * 10 ** (boostDecimals - usdDecimals); // scaled
        }

        if (boostReserve <= usdReserve) revert InvalidReserveRatio({ratio: (FACTOR * usdReserve) / boostReserve});

        uint256 usdNeeded = (((boostReserve - usdReserve) / 2) * usdBuyRatio) / FACTOR;
        uint256 totalLp = IERC20(pool).totalSupply();
        uint256 lpAmount = (usdNeeded * totalLp) / usdReserve;

        // Readjust the LP amount and USD needed to balance price before removing LP
        lpAmount -= lpAmount ** 2 / totalLp;

        (boostRemoved, usdRemoved, boostAmountOut) = ISolidlyV2LiquidityAMO(amoAddress).unfarmBuyBurn(
            lpAmount,
            (lpAmount * boostReserve) / totalLp, // minBoostRemove
            usdNeeded / 10 ** (boostDecimals - usdDecimals), // minUsdRemove
            usdNeeded, // minBoostAmountOut
            block.timestamp + 1 //deadline
        );

        newBoostPrice = ISolidlyV2LiquidityAMO(amoAddress).boostPrice();

        // Checks if the price of boost is less than the boostUpperPriceBuy
        if (newBoostPrice > boostUpperPriceBuy) revert PriceNotInRange(newBoostPrice);

        emit UnfarmBuyBurnExecuted(lpAmount, boostRemoved, usdRemoved, boostAmountOut, newBoostPrice);
    }

    ////////////////////////// SETTER FUNCTIONS //////////////////////////
    /// @inheritdoc ISolidlyV2PublicAMO
    function setBuyAndSellBound(
        uint256 boostUpperPriceBuy_,
        uint256 boostLowerPriceSell_
    ) external onlyRole(SETTER_ROLE) {
        boostUpperPriceBuy = boostUpperPriceBuy_;
        boostLowerPriceSell = boostLowerPriceSell_;
        emit BuyAndSellBoundSet(boostUpperPriceBuy_, boostLowerPriceSell_);
    }

    /// @inheritdoc ISolidlyV2PublicAMO
    function setAmo(address amoAddress_) external onlyRole(SETTER_ROLE) {
        if (amoAddress_ == address(0)) revert ZeroAddress();
        amoAddress = amoAddress_;
        emit AMOSet(amoAddress_);
    }

    /// @inheritdoc ISolidlyV2PublicAMO
    function setToken(uint256 tokenId_, bool useToken_) external onlyRole(SETTER_ROLE) {
        tokenId = tokenId_;
        useToken = useToken_;
        emit TokenSet(tokenId_, useToken_);
    }

    /// @inheritdoc ISolidlyV2PublicAMO
    function setBoostSellRatio(uint256 boostSellRatio_) external onlyRole(SETTER_ROLE) {
        boostSellRatio = boostSellRatio_;
        emit BoostSellRatioSet(boostSellRatio_);
    }

    /// @inheritdoc ISolidlyV2PublicAMO
    function setUsdBuyRatio(uint256 usdBuyRatio_) external onlyRole(SETTER_ROLE) {
        usdBuyRatio = usdBuyRatio_;
        emit UsdBuyRatioSet(usdBuyRatio_);
    }
}
