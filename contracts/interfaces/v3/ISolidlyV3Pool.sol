// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/**
 * @title The interface for a Solidly V3 Pool
 * @notice A Solidly pool facilitates swapping and automated market making between any two assets that strictly conform
 * to the ERC20 specification
 */
interface ISolidlyV3Pool {
    /**
     * @notice Returns the address of the factory that deployed the pool.
     * @return The contract address.
     */
    function factory() external view returns (address);
}
