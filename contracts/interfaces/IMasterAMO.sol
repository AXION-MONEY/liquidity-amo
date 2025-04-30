// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../price-manager/interfaces/IPriceManager.sol";

/**
 * @title IMasterAMO
 * @notice Interface defining core functions, roles, and events for Automated Market Operations (AMO).
 */
interface IMasterAMO {
    // -------------------------------------------------------------
    //                           ERRORS
    // -------------------------------------------------------------

    /// @notice Reverts when an operation is attempted with a zero address.
    error ZeroAddress();

    /// @notice Reverts when an invalid ratio value is provided.
    error InvalidRatioValue();

    /// @notice Reverts when an operation outputs insufficient tokens.
    error InsufficientOutputAmount(uint256 outputAmount, uint256 minRequired);

    /// @notice Reverts when adding liquidity is attempted with an invalid ratio.
    error InvalidRatioToAddLiquidity();

    /// @notice Reverts when the ION price is not within the expected range.
    error PriceNotInRange(uint256 currentPrice, uint256 targetPrice);

    /// @notice Reverts when an operation is attempted but the price is already within the expected range.
    error PriceAlreadyInRange(uint256 currentPrice, uint256 targetPrice);

    error NoRemainingAmount();

    // -------------------------------------------------------------
    //                           EVENTS
    // -------------------------------------------------------------

    /**
     * @notice Emitted when ION is minted and sold for PairToken.
     * @param ionAmountIn The amount of ION minted and sold.
     * @param pairTokenAmountOut The amount of pairToken received.
     */
    event MintSell(uint256 ionAmountIn, uint256 pairTokenAmountOut);

    /**
     * @notice Emitted when the target price premium is updated.
     * @param premium The new premium value.
     */
    event IonTargetPricePremiumSet(uint256 premium);

    /**
     * @notice Emitted when various parameters are set.
     * @param validRangeWidth The valid range width for liquidity addition.
     * @param sellRatio The sell ratio as mintSellFarm's swap ratio.
     * @param buyRatio The buy ratio as unfarmBuyBurn's swap ratio.
     */
    event ParamsSet(uint24 validRangeWidth, uint24 sellRatio, uint24 buyRatio);

    // -------------------------------------------------------------
    //                            ROLES
    // -------------------------------------------------------------
    /// @notice Returns the identifier for the SETTER_ROLE.
    function SETTER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the PAUSER_ROLE.
    function PAUSER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the UNPAUSER_ROLE.
    function UNPAUSER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the WITHDRAWER_ROLE.
    function WITHDRAWER_ROLE() external view returns (bytes32);

    /// @notice Returns the identifier for the OPERATOR_ROLE.
    function OPERATOR_ROLE() external view returns (bytes32);

    // -------------------------------------------------------------
    //                        STATE VARIABLES
    // -------------------------------------------------------------
    /// @notice Address of the ION token.
    function ionAddress() external view returns (address);

    /// @notice Address of the pair token.
    function pairTokenAddress() external view returns (address);

    /// @notice Address of the liquidity pool.
    function poolAddress() external view returns (address);

    /// @notice Number of decimals used by the ION token.
    function ionDecimals() external view returns (uint8);

    /// @notice Number of decimals used by the pair token.
    function pairTokenDecimals() external view returns (uint8);

    /// @notice Address of the ION minter contract.
    function ionMinterAddress() external view returns (address);

    /// @notice Address of the PriceManager Contract.
    function priceManagerContractAddress() external view returns (address);

    /// @notice Type of the PairToken either USD or other Staked Stable types.
    function pairTokenType() external view returns (IPriceManager.TokenType);

    /// @notice Valid range ratio for adding liquidity (6 decimals).
    function validRangeWidth() external view returns (uint24);

    /**
     * @notice Retrieves the current premium offset used for staked pairs in target price calculations.
     * @dev This premium value is added to the preview deposit amount from the PriceManager for staked tokens
     *      to derive the overall target price. It represents the price slippage and is expected to be lower than
     *      the pull fee.
     *
     * @return The current premium offset.
     */
    function ionTargetPricePremium() external view returns (uint256);

    /// @notice Returns the sell ratio as mintSellFarm's swap ratio.
    function sellRatio() external view returns (uint24);

    /// @notice Returns the buy ratio as unfarmBuyBurn's swap ratio.
    function buyRatio() external view returns (uint24);

    // -------------------------------------------------------------
    //                           FUNCTIONS
    // -------------------------------------------------------------
    /**
     * @notice Pauses the contract.
     * @dev Only accounts with PAUSER_ROLE can invoke this.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract.
     * @dev Only accounts with UNPAUSER_ROLE can invoke this.
     */
    function unpause() external;

    /**
     * @notice Sets the premium offset used in target price calculations.
     * @param targetPricePremium_ The new premium offset.
     */
    function setIonTargetPricePremium(uint256 targetPricePremium_) external;

    /**
     * @notice Sets various parameters for AMO operations.
     * @param validRangeWidth_ The valid range width for liquidity addition.
     * @param sellRatio_ The sell ratio as mintSellFarm's swap ratio.
     * @param buyRatio_ The buy ratio as unfarmBuyBurn's swap ratio.
     */
    function setParams(uint24 validRangeWidth_, uint24 sellRatio_, uint24 buyRatio_) external;

    /**
     * @notice Adds liquidity to the ION-PairToken pool, based on the contract's PairToken balance.
     * @return liquidity The liquidity tokens received.
     */
    function addLiquidity() external returns (uint256 liquidity);

    /**
     * @notice Removes liquidity from the ION-PairToken pool.
     * @param liquidity The liquidity amount to remove.
     * @param ionMinRemove The minimum ION amount to remove.
     * @param pairTokenMinRemove The minimum PairToken amount to remove.
     * @param recipient The address of the receiver of the removed pair tokens.
     * @return ionRemoved The ION amount removed.
     * @return pairTokenRemoved The PairToken amount removed.
     * @return ionCollectedFee The ION amount part of the collected fee.
     * @return pairTokenCollectedFee The PairToken amount part of the collected fee.
     */
    function removeLiquidity(
        uint256 liquidity,
        uint256 ionMinRemove,
        uint256 pairTokenMinRemove,
        address recipient
    )
        external
        returns (uint256 ionRemoved, uint256 pairTokenRemoved, uint256 ionCollectedFee, uint256 pairTokenCollectedFee);

    /**
     * @notice Mints, sells, and farms ION tokens when ION is over peg.
     * @return liquidity The liquidity tokens received.
     * @return postOperationIonPrice The new average ION price after the operation.
     */
    function mintSellFarm() external returns (uint256 liquidity, uint256 postOperationIonPrice);

    /**
     * @notice Unfarms liquidity, buys, and burns ION tokens when ION is under peg.
     * @return liquidity The liquidity tokens affected.
     * @return postOperationIonPrice The new average ION price after the operation.
     */
    function unfarmBuyBurn() external returns (uint256 liquidity, uint256 postOperationIonPrice);

    /**
     * @notice Withdraws ERC20 tokens from the contract.
     * @param token The ERC20 token address.
     * @param amount The amount to withdraw.
     * @param recipient The address to receive the tokens.
     */
    function withdrawERC20(address token, uint256 amount, address recipient) external;

    /**
     * @notice Retrieves the current ION price.
     * @return price The current ION price divided by the oracle price of the paired token (using 6 decimals).
     */
    function ionPriceInPairToken() external view returns (uint256 price);

    /**
     * @notice Retrieves the target price for ION relative to the oracle price of the paired token.
     * @dev The target price is determined as follows:
     *      - For a STABLE pair token, the target price is set to a fixed base unit (1 × 10^PRICE_DECIMALS).
     *      - For staked pairs (SUSDE, SFRAX, SDAI), the target price is calculated by querying the corresponding
     *        preview deposit function from the PriceManager using the base unit, and then adding a price offset
     *        (targetPricePremium). This premium represents a slippage adjustment and must be set lower than the pull fee.
     *
     * @return The computed target price.
     */
    function ionTargetPriceInPairToken() external view returns (uint256);
}
