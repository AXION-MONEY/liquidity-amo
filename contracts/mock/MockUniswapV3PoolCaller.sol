// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "../interfaces/v3/IUniswapV3Pool.sol";
import {IMinter} from "../interfaces/IMinter.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract MockUniswapV3PoolCaller {
    using SafeERC20 for IERC20;

    address public poolAddress;
    address public token0;
    address public token1;

    constructor(address _poolAddress) {
        poolAddress = _poolAddress;
        token0 = IUniswapV3Pool(_poolAddress).token0();
        token1 = IUniswapV3Pool(_poolAddress).token1();
    }

    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = IUniswapV3Pool(poolAddress).mint(
            recipient,
            tickLower,
            tickUpper,
            amount,
            abi.encode(msg.sender)
        );
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) external returns (int256 amount0, int256 amount1) {
        (amount0, amount1) = IUniswapV3Pool(poolAddress).swap(
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );
    }

    function solidlyV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    function ramsesV2SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        _swapCallback(amount0Delta, amount1Delta, data);
    }

    function _swapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) internal {
        address spender = abi.decode(data, (address));
        if (amount0Delta < 0) IERC20(token1).safeTransferFrom(spender, poolAddress, uint256(amount1Delta));
        else IERC20(token0).safeTransferFrom(spender, poolAddress, uint256(amount0Delta));
    }

    function solidlyV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    function ramsesV2MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    function algebraMintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        _mintCallback(amount0Owed, amount1Owed, data);
    }

    function _mintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) internal {
        address spender = abi.decode(data, (address));
        IERC20(token0).safeTransferFrom(spender, poolAddress, amount0Owed);
        IERC20(token1).safeTransferFrom(spender, poolAddress, amount1Owed);
    }
}
