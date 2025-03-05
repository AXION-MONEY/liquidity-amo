// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPairFactory {
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);

    function getFee(bool) external view returns (uint256);
}
