// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockGauge {
    function deposit(uint256 amount, uint256 tokenId) external {}

    function deposit(uint256 amount) external {}

    function withdraw(uint256 amount) external {}

    function getReward(address _account) external {}

    function getReward(address account, address[] memory tokens) external {}

    function getReward(uint256 tokenId) external {}

    function getReward() external {}

    function balanceOf(address) external view returns (uint256) {}
}
