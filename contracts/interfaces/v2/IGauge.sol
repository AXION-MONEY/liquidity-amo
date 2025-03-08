// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IGauge {
    function deposit(uint256 amount, uint256 tokenId) external;

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward(address _account) external;

    function getReward(address account, address[] memory tokens) external;

    function getReward(uint256 tokenId) external;

    function getReward() external;
}
