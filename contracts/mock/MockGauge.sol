// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockGauge {
    using SafeERC20 for IERC20;

    IERC20 public token;
    bool public paused;
    mapping(address => uint256) internal _balances;

    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    constructor(address token_) {
        token = IERC20(token_);
        paused = false;
    }

    function pause() external {
        paused = true;
    }

    function unpause() external {
        paused = false;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function deposit(uint256 amount, uint256 tokenId) external whenNotPaused {
        token.safeTransferFrom(msg.sender, address(this), amount);
        _balances[msg.sender] += amount;
    }

    function deposit(uint256 amount) external whenNotPaused {
        token.safeTransferFrom(msg.sender, address(this), amount);
        _balances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external whenNotPaused {
        require(_balances[msg.sender] >= amount, "insufficient balance");
        _balances[msg.sender] -= amount;
        token.safeTransfer(msg.sender, amount);
    }

    function getReward(address _account) external {}

    function getReward(address account, address[] memory tokens) external {}

    function getReward(uint256 tokenId) external {}

    function getReward() external {}

    function balanceOf(address) external view returns (uint256) {}
}
