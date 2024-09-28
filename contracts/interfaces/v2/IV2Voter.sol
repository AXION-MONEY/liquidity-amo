// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IV2Voter {
    function createGauge(address _pool) external returns (address);
}
