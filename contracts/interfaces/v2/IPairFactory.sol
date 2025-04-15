// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IPairFactory {
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);

    function getFee(bool) external view returns (uint256);

    function stableFees() external view returns (uint256);

    function volatileFees() external view returns (uint256);
}
