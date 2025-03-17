// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../interfaces/IMinter.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract MockMinterCaller {
    using SafeERC20 for IERC20;

    address public ionAddress;
    address public collateralAddress;
    address public minterAddress;
    uint8 public ionDecimals;
    uint8 public collateralDecimals;

    constructor(address minterAddress_, address ionAddress_, address collateralAddress_) {
        minterAddress = minterAddress_;
        ionAddress = ionAddress_;
        collateralAddress = collateralAddress_;
        ionDecimals = IERC20Metadata(ionAddress_).decimals();
        collateralDecimals = IERC20Metadata(collateralAddress_).decimals();
    }

    function testMint(address to, uint256 amount) external {
        IERC20(collateralAddress).safeTransferFrom(
            msg.sender,
            address(this),
            amount / (10 ** (ionDecimals - collateralDecimals))
        );
        IERC20(collateralAddress).approve(minterAddress, amount / (10 ** (ionDecimals - collateralDecimals)));
        IMinter(minterAddress).mint(to, amount);
    }

    function testProtocolMint(address to, uint256 amount) external {
        IMinter(minterAddress).protocolMint(to, amount);
    }
}
