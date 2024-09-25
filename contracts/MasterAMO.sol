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

abstract contract MasterAMO is
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== ERRORS ========== */
    error ZeroAddress();

    /* ========== ROLES ========== */
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant AMO_ROLE = keccak256("AMO_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /* ========== VARIABLES ========== */
    address public boost;
    address public usd;
    address public pool;
    uint8 public boostDecimals;
    uint8 public usdDecimals;
    address public boostMinter;

    uint256 public boostMultiplier; // decimals 6
    uint24 public validRangeRatio; // decimals 6
    uint24 public validRemovingRatio; // decimals 6

    uint256 public boostLowerPriceSell; // decimals 6
    uint256 public boostUpperPriceBuy; // decimals 6

    /* ========== CONSTANTS ========== */
    uint8 internal constant PRICE_DECIMALS = 6;
    uint8 internal constant PARAMS_DECIMALS = 6;
    uint256 internal constant FACTOR = 10 ** PARAMS_DECIMALS;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,
        address boost_,
        address usd_,
        address pool_,
        address boostMinter_
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        if (
            admin == address(0) ||
            boost_ == address(0) ||
            usd_ == address(0) ||
            pool_ == address(0) ||
            boostMinter_ == address(0)
        ) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        boost = boost_;
        usd = usd_;
        pool = pool_;
        boostDecimals = IERC20Metadata(boost).decimals();
        usdDecimals = IERC20Metadata(usd).decimals();
        boostMinter = boostMinter_;
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
    function _mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) internal virtual returns (uint256 boostAmountIn, uint256 usdAmountOut);

    function mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 deadline
    ) external onlyRole(AMO_ROLE) whenNotPaused nonReentrant returns (uint256 boostAmountIn, uint256 usdAmountOut) {
        (boostAmountIn, usdAmountOut) = _mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);
    }

    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    ) internal virtual returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity);

    function addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        external
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        (boostSpent, usdSpent, liquidity) = _addLiquidity(usdAmount, minBoostSpend, minUsdSpend, deadline);
    }

    function _mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        internal
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        (boostAmountIn, usdAmountOut) = _mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);

        uint256 price = boostPrice();
        if (price > FACTOR - validRangeRatio && price < FACTOR + validRangeRatio) {
            uint256 usdBalance = IERC20Upgradeable(usd).balanceOf(address(this));
            (boostSpent, usdSpent, liquidity) = _addLiquidity(usdBalance, minBoostSpend, minUsdSpend, deadline);
        }
    }

    function mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        external
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostAmountIn, uint256 usdAmountOut, uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        (boostAmountIn, usdAmountOut, boostSpent, usdSpent, liquidity) = _mintSellFarm(
            boostAmount,
            minUsdAmountOut,
            minBoostSpend,
            minUsdSpend,
            deadline
        );
    }

    function _unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    ) internal virtual returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut);

    function unfarmBuyBurn(
        uint256 liquidity,
        uint256 minBoostRemove,
        uint256 minUsdRemove,
        uint256 minBoostAmountOut,
        uint256 deadline
    )
        external
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostRemoved, uint256 usdRemoved, uint256 usdAmountIn, uint256 boostAmountOut)
    {
        (boostRemoved, usdRemoved, usdAmountIn, boostAmountOut) = _unfarmBuyBurn(
            liquidity,
            minBoostRemove,
            minUsdRemove,
            minBoostAmountOut,
            deadline
        );
    }

    ////////////////////////// PUBLIC FUNCTIONS //////////////////////////
    function mintSellFarm() external virtual returns (uint256 liquidity, uint256 newBoostPrice);

    function unfarmBuyBurn() external virtual returns (uint256 liquidity, uint256 newBoostPrice);

    ////////////////////////// Withdrawal functions //////////////////////////
    function withdrawERC20(address token, uint256 amount, address recipient) external onlyRole(WITHDRAWER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        IERC20Upgradeable(token).safeTransfer(recipient, amount);
    }

    function withdrawERC721(address token, uint256 tokenId_, address recipient) external onlyRole(WITHDRAWER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        IERC721Upgradeable(token).safeTransferFrom(address(this), recipient, tokenId_);
    }

    ////////////////////////// Internal functions //////////////////////////
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
    function boostPrice() public view virtual returns (uint256 price);
}
