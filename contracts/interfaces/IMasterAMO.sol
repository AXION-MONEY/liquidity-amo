// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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

    /// @notice Reverts when the ION price is not within an expected range.
    error PriceNotInRange(uint256 price);

    /// @notice Reverts when an operation is attempted but the price is already within the expected range.
    error PriceAlreadyInRange(uint256 price);

    /// @notice Reverts when an unsupported pair token type is used.
    error InvalidPairTokenType();

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
    event SetIonTargetPricePremium(uint256 premium);

    // -------------------------------------------------------------
    //                           ENUMS
    // -------------------------------------------------------------
    enum PairTokenType {
        STABLE,
        SUSDE,
        SFRAX,
        SDAI
    }

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
    function pairTokenType() external view returns (PairTokenType);

    /// @notice ION multiplier (scaled to 6 decimals).
    function ionMultiplayer() external view returns (uint256);

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
     * @notice Adds liquidity to the ION-PairToken pool, based on the contract's PairToken balance.
     * @return liquidity The liquidity tokens received.
     */
    function addLiquidity() external returns (uint256 liquidity);

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
     * @return price The current ION price (using 6 decimals).
     */
    function ionPrice() external view returns (uint256 price);

    /**
     * @notice Retrieves the target price for ION based on the paired token type.
     * @dev The target price is determined as follows:
     *      - For a STABLE pair token, the target price is set to a fixed base unit (1 × 10^PRICE_DECIMALS).
     *      - For staked pairs (SUSDE, SFRAX, SDAI), the target price is calculated by querying the corresponding
     *        preview deposit function from the PriceManager using the base unit, and then adding a price offset
     *        (targetPricePremium). This premium represents a slippage adjustment and must be set lower than the pull fee.
     *
     * @return price The computed target price.
     */
    function ionTargetPrice() external view returns (uint256 price);
}
