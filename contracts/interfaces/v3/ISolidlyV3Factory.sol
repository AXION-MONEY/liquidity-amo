// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/**
 * @title The interface for the Solidly V3 Factory
 * @notice The Solidly V3 Factory facilitates creation of Solidly V3 pools and control over the protocol fees
 */
interface ISolidlyV3Factory {
    /**
     * @notice Returns the current fee collector of the factory
     * @dev Can be changed by the current owner via setFeeCollector.
     * @return The address of the fee collector.
     */
    function feeCollector() external view returns (address);
}
