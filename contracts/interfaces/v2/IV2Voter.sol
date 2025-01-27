// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IV2Voter {
    function createGauge(address _pool) external returns (address);
    function governor() external view returns (address);
    function gauges(address _pool) external view returns (address);
}
