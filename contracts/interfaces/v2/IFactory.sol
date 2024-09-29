// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFactory {
    function createPair(address tokenA, address tokenB, bool stable) external returns (address);
}
