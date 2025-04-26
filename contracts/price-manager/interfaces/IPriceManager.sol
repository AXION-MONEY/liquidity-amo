// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libs/StakedUSDeLib.sol";
import "../libs/StakedFraxLib.sol";
import "../libs/SavingsDaiLib.sol";
import "../muon/interfaces/IMuonClient.sol";

/**
 * @title IPriceManager
 * @notice Interface defining core functions, errors, events, and structs for managing staked asset prices.
 */
interface IPriceManager {
    // -------------------------------------------------------------
    //                           ERRORS
    // -------------------------------------------------------------
    /**
     * @notice Thrown when a zero address is provided.
     */
    error ZeroAddress();

    /**
     * @notice Thrown when the last distribution timestamp is invalid.
     */
    error InvalidLastDistribution();

    /**
     * @notice Thrown when the provided source block timestamp is older than or equal to the last processed timestamp.
     * @param srcBlockTimestamp The timestamp of the source block.
     * @param lastBlockTimestamp The timestamp of the last processed block.
     */
    error OldBlock(uint256 srcBlockTimestamp, uint256 lastBlockTimestamp);

    /**
     * @notice Thrown when the source block timestamp is in the future.
     * @param srcBlockTimestamp The timestamp of the source block.
     * @param currentBlockTimestamp The current block timestamp.
     */
    error InvalidBlock(uint256 srcBlockTimestamp, uint256 currentBlockTimestamp);

    /**
     * @notice Thrown when the token provided in the signature does not match the expected token.
     */
    error SigTokenMismatch();

    /**
     * @notice Thrown when the stable price value is not in the valid range.
     */
    error InvalidPriceValue();

    /**
     * @notice Thrown when an unsupported token type is used.
     */
    error InvalidTokenType();

    // -------------------------------------------------------------
    //                           EVENTS
    // -------------------------------------------------------------
    /**
     * @notice Emitted when the Muon client address is set.
     * @param muonClientAddress The address of the Muon client.
     */
    event SetMuonClient(address muonClientAddress);

    /**
     * @notice Emitted when stablecoin valid price boundaries are set.
     * @param stablePriceLower The minimum valid price value.
     * @param stablePriceUpper The maximum valid price value.
     */
    event StablePriceBoundsSet(uint256 stablePriceLower, uint256 stablePriceUpper);

    /**
     * @notice Emitted when the sUSDe state is updated.
     * @param newStates The new state of sUSDe.
     * @param srcBlock The block reference associated with the update.
     */
    event SUsdeSet(StakedUSDeLib.StakedUSDe newStates, Block srcBlock);

    /**
     * @notice Emitted when the sFRAX state is updated.
     * @param newStates The new state of sFRAX.
     * @param srcBlock The block reference associated with the update.
     */
    event SFraxSet(StakedFraxLib.StakedFrax newStates, Block srcBlock);

    /**
     * @notice Emitted when the Savings DAI pot state is updated.
     * @param newStates The new state of the Savings DAI pot.
     * @param srcBlock The block reference associated with the update.
     */
    event PotSet(SavingsDaiLib.Pot newStates, Block srcBlock);

    // -------------------------------------------------------------
    //                          STRUCTS
    // -------------------------------------------------------------
    /**
     * @notice Struct representing a block reference.
     * @param number The block number.
     * @param timestamp The block timestamp.
     */
    struct Block {
        uint256 number;
        uint256 timestamp;
    }

    /**
     * @notice Struct representing a stablecoin price data.
     * @param price The price of the stablecoin.
     * @param timestamp The timestamp of the price.
     */
    struct StablePrice {
        uint256 price;
        uint256 timestamp;
    }

    /**
     * @notice Struct representing a Muon signature payload.
     * @param srcBlock The block reference from which the signature was generated.
     * @param reqId The request ID.
     * @param signature The Schnorr signature provided by the Muon client.
     * @param gatewaySignature The gateway signature.
     * @param token The expected token identifier string.
     */
    struct MuonSig {
        Block srcBlock;
        bytes reqId;
        IMuonClient.SchnorrSign signature;
        bytes gatewaySignature;
        string token;
    }

    // -------------------------------------------------------------
    //                           ENUMS
    // -------------------------------------------------------------
    enum TokenType {
        STABLE,
        SUSDE,
        SFRAX,
        SDAI
    }

    // -------------------------------------------------------------
    //                            ROLES
    // -------------------------------------------------------------
    /// @notice Role for accounts allowed to update asset states.
    function TOKEN_UPDATER_ROLE() external view returns (bytes32);

    /// @notice Role for accounts allowed to set configuration parameters.
    function SETTER_ROLE() external view returns (bytes32);

    // -------------------------------------------------------------
    //                       FUNCTIONS
    // -------------------------------------------------------------
    /**
     * @notice Sets (or re-sets) the Muon client address.
     * @dev Callable only by an account with SETTER_ROLE.
     * @param _muonClientAddress The address of the Muon client.
     */
    function setMuonClient(address _muonClientAddress) external;

    /**
     * @notice Sets stablecoin valid price boundaries.
     * @param _stablePriceLower The minimum valid price value.
     * @param _stablePriceUpper The maximum valid price value.
     */
    function setStablePriceBounds(uint256 _stablePriceLower, uint256 _stablePriceUpper) external;

    ////// Stablecoins SET Price Values FUNCTIONS //////
    /**
     * @notice Updates a stablecoin price.
     * @dev Callable only by an account with TOKEN_UPDATER_ROLE.
     * @param tokenAddress The stablecoin address to set the price.
     * @param price The price.
     */
    function setStable(address tokenAddress, uint256 price) external;

    /**
     * @notice Updates a stablecoin price using off-chain signature verification.
     * @param tokenAddress The stablecoin address to set the price.
     * @param price The price.
     * @param sig The Muon signature payload.
     */
    function setStableWithSig(address tokenAddress, uint256 price, MuonSig calldata sig) external;

    ////// SUsde SET Price Values FUNCTIONS //////
    /**
     * @notice Updates the sUSDe state.
     * @dev Callable only by an account with TOKEN_UPDATER_ROLE.
     * @param _sUSDe The new sUSDe state.
     * @param srcBlock The block reference associated with the update.
     */
    function setSUsde(StakedUSDeLib.StakedUSDe calldata _sUSDe, Block calldata srcBlock) external;

    /**
     * @notice Updates the sUSDe state using off-chain signature verification.
     * @param _sUSDe The new sUSDe state.
     * @param sig The Muon signature payload.
     */
    function setSUsdeWithSig(StakedUSDeLib.StakedUSDe calldata _sUSDe, MuonSig calldata sig) external;

    ////// SFRAX SET Price Values FUNCTIONS //////
    /**
     * @notice Updates the sFRAX state.
     * @dev Callable only by an account with TOKEN_UPDATER_ROLE.
     * @param _sFRAX The new sFRAX state.
     * @param srcBlock The block reference associated with the update.
     */
    function setSFrax(StakedFraxLib.StakedFrax calldata _sFRAX, Block calldata srcBlock) external;
    /**
     * @notice Updates the sFRAX state using off-chain signature verification.
     * @param _sFRAX The new sFRAX state.
     * @param sig The Muon signature payload.
     */
    function setSFraxWithSig(StakedFraxLib.StakedFrax calldata _sFRAX, MuonSig calldata sig) external;

    ////// SDAI SET Price Values FUNCTIONS //////
    /**
     * @notice Updates the Savings DAI pot state.
     * @dev Callable only by an account with TOKEN_UPDATER_ROLE.
     * @param _pot The new Savings DAI pot state.
     * @param srcBlock The block reference associated with the update.
     */
    function setPot(SavingsDaiLib.Pot calldata _pot, Block calldata srcBlock) external;
    /**
     * @notice Updates the Savings DAI pot state using off-chain signature verification.
     * @param _pot The new Savings DAI pot state.
     * @param sig The Muon signature payload.
     */
    function setPotWithSig(SavingsDaiLib.Pot calldata _pot, MuonSig calldata sig) external;
    // -------------------------------------------------------------
    //                       VIEW FUNCTIONS
    // -------------------------------------------------------------
    /**
     * @notice Returns the price of a specific stablecoin.
     * @param token The stablecoin address.
     * @return price The price in 6 decimals.
     */
    function stableTokenPrice(address token) external view returns (uint256 price);

    /**
     * @notice Returns the price of a specific staked token.
     * @param tokenType The staked token type.
     * @return The price in 6 decimals.
     */
    function stakedTokenPrice(TokenType tokenType) external view returns (uint256);

    /**
     * @notice Returns the underlying assets redeemable for a given amount of sUSDe shares.
     * @param shares The number of sUSDe shares.
     * @return assets The amount of underlying assets.
     */
    function sUsdePreviewRedeem(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns the number of sUSDe shares minted for a given asset deposit.
     * @param assets The amount of assets to deposit.
     * @return shares The number of sUSDe shares.
     */
    function sUsdePreviewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Returns the underlying assets redeemable for a given amount of sFRAX shares.
     * @param shares The number of sFRAX shares.
     * @return assets The amount of underlying assets.
     */
    function sFraxPreviewRedeem(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns the number of sFRAX shares minted for a given asset deposit.
     * @param assets The amount of assets to deposit.
     * @return shares The number of sFRAX shares.
     */
    function sFraxPreviewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @notice Returns the underlying assets redeemable for a given amount of Savings DAI shares.
     * @param shares The number of Savings DAI shares.
     * @return assets The amount of underlying assets.
     */
    function sDaiPreviewRedeem(uint256 shares) external view returns (uint256 assets);

    /**
     * @notice Returns the number of Savings DAI shares minted for a given asset deposit.
     * @param assets The amount of assets to deposit.
     * @return shares The number of Savings DAI shares.
     */
    function sDaiPreviewDeposit(uint256 assets) external view returns (uint256 shares);
}
