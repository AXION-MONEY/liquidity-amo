// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IPair {
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
}
