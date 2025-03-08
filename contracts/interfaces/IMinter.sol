// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMinter Interface
 * @notice Interface for the Minter contract, defining errors, roles, events, state variable getters, and function signatures.
 */
interface IMinter {
    // -------------------------------------------------------------
    //                          ERRORS
    // -------------------------------------------------------------
    /// @notice Thrown when an address provided is zero.
    error ZeroAddress();
    /// @notice Thrown when the caller is not a contract.
    error NonContractSender();

    // -------------------------------------------------------------
    //                            ROLES
    // -------------------------------------------------------------
    /**
     * @notice Returns the identifier for the MINTER_ROLE.
     * @dev MINTER_ROLE allows designated contracts to call mint().
     */
    function MINTER_ROLE() external view returns (bytes32);
    /**
     * @notice Returns the identifier for the ADMIN_ROLE.
     * @dev ADMIN_ROLE allows designated accounts to update token addresses.
     */
    function ADMIN_ROLE() external view returns (bytes32);
    /**
     * @notice Returns the identifier for the AMO_ROLE.
     * @dev AMO_ROLE allows designated contracts to perform protocol minting.
     */
    function AMO_ROLE() external view returns (bytes32);
    /**
     * @notice Returns the identifier for the PAUSER_ROLE.
     * @dev PAUSER_ROLE allows designated accounts to pause the contract.
     */
    function PAUSER_ROLE() external view returns (bytes32);
    /**
     * @notice Returns the identifier for the UNPAUSER_ROLE.
     * @dev UNPAUSER_ROLE allows designated accounts to unpause the contract.
     */
    function UNPAUSER_ROLE() external view returns (bytes32);
    /**
     * @notice Returns the identifier for the WITHDRAWER_ROLE.
     * @dev WITHDRAWER_ROLE allows designated accounts to withdraw tokens.
     */
    function WITHDRAWER_ROLE() external view returns (bytes32);

    // -------------------------------------------------------------
    //                     STATE VARIABLE
    // -------------------------------------------------------------
    /**
     * @notice Returns the address of the BOOST token.
     */
    function boostAddress() external view returns (address);
    /**
     * @notice Returns the address of the collateral token.
     */
    function collateralAddress() external view returns (address);
    /**
     * @notice Returns the treasury address.
     */
    function treasury() external view returns (address);
    /**
     * @notice Returns the number of decimals used by the BOOST token.
     */
    function boostDecimals() external view returns (uint8);
    /**
     * @notice Returns the number of decimals used by the collateral token.
     */
    function collateralDecimals() external view returns (uint8);

    // -------------------------------------------------------------
    //                           EVENTS
    // -------------------------------------------------------------
    /**
     * @notice Emitted when the token addresses for BOOST and collateral are updated.
     * @param boostAddress The new BOOST token address.
     * @param collateralAddress The new collateral token address.
     */
    event TokenAddressesUpdated(address indexed boostAddress, address indexed collateralAddress);
    /**
     * @notice Emitted when the treasury address is updated.
     * @param newTreasury The new treasury address.
     */
    event TreasuryUpdated(address newTreasury);
    /**
     * @notice Emitted when tokens are minted.
     * @param user The address initiating the mint.
     * @param to The recipient of the minted tokens.
     * @param amount The amount minted.
     */
    event TokenMinted(address indexed user, address indexed to, uint256 amount);
    /**
     * @notice Emitted when protocol minting occurs.
     * @param user The address initiating the protocol mint.
     * @param to The recipient of the minted tokens.
     * @param amount The amount minted.
     */
    event TokenProtocolMinted(address indexed user, address indexed to, uint256 amount);
    /**
     * @notice Emitted when tokens are withdrawn.
     * @param tokenAddress The token address.
     * @param amount The amount withdrawn.
     */
    event TokenWithdrawn(address indexed tokenAddress, uint256 amount);

    // -------------------------------------------------------------
    //                     FUNCTION SIGNATURES
    // -------------------------------------------------------------
    /**
     * @notice Pauses the contract.
     */
    function pause() external;
    /**
     * @notice Unpauses the contract.
     */
    function unpause() external;
    /**
     * @notice Sets the BOOST and collateral token addresses.
     * @param boost The new BOOST token address.
     * @param collateral The new collateral token address.
     */
    function setTokens(address boost, address collateral) external;
    /**
     * @notice Sets the treasury address.
     * @param treasury The new treasury address.
     */
    function setTreasury(address treasury) external;
    /**
     * @notice Mints BOOST tokens by transferring collateral and then minting BOOST.
     * @param to The address to receive minted BOOST.
     * @param amount The amount of BOOST to mint.
     */
    function mint(address to, uint256 amount) external;
    /**
     * @notice Mints BOOST tokens via protocol operations.
     * @param to The address to receive minted BOOST.
     * @param amount The amount of BOOST to mint.
     */
    function protocolMint(address to, uint256 amount) external;
    /**
     * @notice Withdraws a specified token amount to the treasury.
     * @param token The token address.
     * @param amount The amount to withdraw.
     */
    function withdrawToken(address token, uint256 amount) external;
}
