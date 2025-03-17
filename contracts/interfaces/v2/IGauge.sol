// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IGauge {
    function deposit(uint256 amount, uint256 tokenId) external; // Ramses, Solidly

    function deposit(uint256 amount) external; // Equalizer, Velo, Thena

    function withdraw(uint256 amount) external;

    function getReward(address _account) external; // Velo

    function getReward(address account, address[] memory tokens) external; // Ramses, Solidly

    function getReward() external; // Equalizer, Thena
}
