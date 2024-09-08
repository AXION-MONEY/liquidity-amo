// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IERC20 {
    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);
}
