// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title IIon.sol Interface
 * @notice Interface for the Ion.sol contract, defining roles and functions for minting and burning tokens.
 */
interface IIon is IERC20 {
    // -------------------------------------------------------------
    //                            ROLES
    // -------------------------------------------------------------
    /**
     * @notice Returns the identifier for the MINTER_ROLE.
     * @dev MINTER_ROLE allows designated accounts to mint new tokens.
     */
    function MINTER_ROLE() external view returns (bytes32);
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

    // -------------------------------------------------------------
    //                     FUNCTION SIGNATURES
    // -------------------------------------------------------------
    /**
     * @dev Destroys a `value` amount of tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 value) external;

    /**
     * @dev Destroys a `value` amount of tokens from `account`, deducting from
     * the caller's allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `value`.
     */
    function burnFrom(address account, uint256 value) external;

    /**
     * @notice Mints a specified amount of tokens to a given address.
     * @dev Can only be called by an account with the MINTER_ROLE.
     * @param to The address to receive the minted tokens.
     * @param amount The amount to mint.
     */
    function mint(address to, uint256 amount) external;
}
