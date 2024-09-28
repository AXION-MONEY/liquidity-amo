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
import {IMinter} from "./interfaces/IMinter.sol";
import {IBoostStablecoin} from "./interfaces/IBoostStablecoin.sol";
import {IMasterAMO} from "./interfaces/IMasterAMO.sol";

/**
* the contracts are upgradable but behind a time lock. This is because we plan further improvements to the AMO logic ( we could for instance deploy an AMO cotract for concentrated liquidity).
* in future versions, upgrades could be strictly tied to a governance vote (where upgrade can only be passed with testified governance vote approval)
* the contracts are pausable — also governance-unpausable to ensure decentralisation
**/

abstract contract MasterAMO is
    IMasterAMO,
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
    error PriceNotInRange(uint256 price);

    /* ========== EVENTS ========== */
    event MintSell(uint256 boostAmountIn, uint256 usdAmountOut);
    event PublicMintSellFarmExecuted(uint256 liquidity, uint256 newBoostPrice);
    event PublicUnfarmBuyBurnExecuted(uint256 liquidity, uint256 newBoostPrice);

    /* ========== ROLES ========== */
    /// @inheritdoc IMasterAMO
    bytes32 public constant override SETTER_ROLE = keccak256("SETTER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override AMO_ROLE = keccak256("AMO_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    /// @inheritdoc IMasterAMO
    bytes32 public constant override WITHDRAWER_ROLE = keccak256("WITHDRAWER_ROLE");

    /* ========== VARIABLES ========== */
    /// @inheritdoc IMasterAMO
    address public override boost;
    /// @inheritdoc IMasterAMO
    address public override usd;
    /// @inheritdoc IMasterAMO
    address public override pool;
    /// @inheritdoc IMasterAMO
    uint8 public override boostDecimals;
    /// @inheritdoc IMasterAMO
    uint8 public override usdDecimals;
    /// @inheritdoc IMasterAMO
    address public override boostMinter;

    /// @inheritdoc IMasterAMO
    uint256 public override boostMultiplier;
    /// @inheritdoc IMasterAMO
    uint24 public override validRangeRatio;
    /// @inheritdoc IMasterAMO
    uint24 public override validRemovingRatio;

    /// @inheritdoc IMasterAMO
    uint256 public override boostLowerPriceSell;
    /// @inheritdoc IMasterAMO
    uint256 public override boostUpperPriceBuy;

    /* ========== CONSTANTS ========== */
    uint8 internal constant PRICE_DECIMALS = 6;
    uint8 internal constant PARAMS_DECIMALS = 6;
    uint256 internal constant FACTOR = 10 ** PARAMS_DECIMALS;

    /* ========== FUNCTIONS ========== */
    function initialize(
        address admin,       // admin role given is given to multisig exclusively
        address boost_,      // the stable coin
        address usd_,        // generic name for $1 collateral ( typically USDC or USDT )
        address pool_,       // the AMO logic appliues on a given Boost-USD pool 
        // on each chain where boost is deployed, there will be one stable Boost-USD pool which guarantees BOOST's peg
        // there can be multiple Boost-Usd pool (which each it's AMO) if two major Dexes on one chain, peg is guaranteed independently on the two pools
        address boostMinter_ // the minter conrtact
    ) public initializer {
        __AccessControlEnumerable_init();
        __Pausable_init();
        if (
            admin == address(0) ||
            boost_ == address(0) ||
            usd_ == address(0) ||
            pool_ == address(0) ||
            boostMinter_ == address(0)
        ) revert ZeroAddress(); //zero-address error checks

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        boost = boost_;
        usd = usd_;
        pool = pool_;
        boostDecimals = IERC20Metadata(boost).decimals();
        usdDecimals = IERC20Metadata(usd).decimals();
        boostMinter = boostMinter_;
    }

    ////////////////////////// PAUSE ACTIONS //////////////////////////
    /// @inheritdoc IMasterAMO
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IMasterAMO
    function unpause() external override onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    ////////////////////////// AMO_ROLE ACTIONS //////////////////////////
/**
* I) When Boost is over peg (in the AMOed pool)
* 1.a) Boost can minted and sold for USD — this is the mintAndSellBoost() function
* 1.b) When peg is restored, the USD 'Backing" (we received from (a) ) is paired with free-minted Boost — it is added farmed with the addLiquidity function
* II) When Boost is under peg
* 2.a) the algo
* 2.b) 
* Implementation: the actions to maintain peg ( I and II ) can be triggered permissionlessly
**/


    function _mintAndSellBoost(
        uint256 boostAmount,
        uint256 minUsdAmountOut, //  boost is only sold over peg ( checked performed whatever minUsdAmountOut is inputted to this function —— this variable can sometimes be omited )
        // the price check is always performed in the implementation contracts XXX TBD could be in the master too
        uint256 deadline
    ) internal virtual returns (uint256 boostAmountIn, uint256 usdAmountOut);

    /// @inheritdoc IMasterAMO
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
        returns (uint256 boostAmountIn, uint256 usdAmountOut)
    {
        (boostAmountIn, usdAmountOut) = _mintAndSellBoost(boostAmount, minUsdAmountOut, deadline);
    }

    function _addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,  // xxx
        uint256 minUsdSpend,    // xxx
        uint256 deadline
    ) internal virtual returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity);

    /// @inheritdoc IMasterAMO
    function addLiquidity(
        uint256 usdAmount,
        uint256 minBoostSpend,    // xxx
        uint256 minUsdSpend,      // xxx
        uint256 deadline
    )
        external
        override
        onlyRole(AMO_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 boostSpent, uint256 usdSpent, uint256 liquidity)
    {
        (boostSpent, usdSpent, liquidity) = _addLiquidity(usdAmount, minBoostSpend, minUsdSpend, deadline);
    }

    function _mintSellFarm( 
    /**
    * combines MintAndSell and addLiquidity
    * addLiquidity only can be performed when price is close to peg (within range)
    * mintAndSell will be looped as long as price remains too far above peg
    **/
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

    /// @inheritdoc IMasterAMO
    function mintSellFarm(
        uint256 boostAmount,
        uint256 minUsdAmountOut,
        uint256 minBoostSpend,
        uint256 minUsdSpend,
        uint256 deadline
    )
        external
        override
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

    /// @inheritdoc IMasterAMO
    function unfarmBuyBurn(
        uint256 liquidity,
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

    ////////////////////////// WITHDRAWAL FUNCTIONS //////////////////////////
    /// @inheritdoc IMasterAMO
    function withdrawERC20(
        address token,
        uint256 amount,
        address recipient
    ) external override onlyRole(WITHDRAWER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        IERC20Upgradeable(token).safeTransfer(recipient, amount);
    }

    /// @inheritdoc IMasterAMO
    function withdrawERC721(
        address token,
        uint256 tokenId_,
        address recipient
    ) external override onlyRole(WITHDRAWER_ROLE) {
        if (recipient == address(0)) revert ZeroAddress();
        IERC721Upgradeable(token).safeTransferFrom(address(this), recipient, tokenId_);
    }

    ////////////////////////// INTERNAL FUNCTIONS //////////////////////////
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

    ////////////////////////// VIEW FUNCTIONS //////////////////////////
    function boostPrice() public view virtual returns (uint256 price);
}
