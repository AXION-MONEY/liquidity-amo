// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IPoolFactory {
    /**
     * @notice Returns the fee for a pool (custom fees are possible).
     */
    function getFee(address _pool, bool _stable) external view returns (uint256);
}
