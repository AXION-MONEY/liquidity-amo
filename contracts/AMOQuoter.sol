pragma solidity 0.8.19;

import "hardhat/console.sol";
import "./interfaces/v3/IV3AMO.sol";

contract AMOQuoter {
    uint256 internal constant FACTOR = 10 ** 6;
    address amo;
    error ubbStats(uint256 blockTimestamp, uint256 liquidityUsed, uint256 excessiveLiquidity, uint256 newPrice);

    constructor(address amo_) {
        amo = amo_;
    }

    function revertCall(uint256 liquidity) external {
        (uint256 oldLiquidity, , ) = IV3AMO(amo).position();
        IMasterAMO(amo).unfarmBuyBurn(liquidity, 1, 1);
        (uint256 newLiquidity, , ) = IV3AMO(amo).position();
        uint256 liquidityUsed = oldLiquidity - newLiquidity;
        revert ubbStats(block.timestamp, liquidityUsed, liquidity - liquidityUsed, IMasterAMO(amo).boostPrice());
    }

    function afterUBB(
        uint256 liquidity
    ) public returns (uint256 liquidityUsed, uint256 excessiveLiquidity, uint256 newPrice) {
        uint256 blockTimestamp;
        try this.revertCall(liquidity) {} catch (bytes memory reason) {
            assembly {
                reason := add(reason, 4)
            }
            (blockTimestamp, liquidityUsed, excessiveLiquidity, newPrice) = abi.decode(
                reason,
                (uint256, uint256, uint256, uint256)
            );
            if (block.timestamp != blockTimestamp) revert(abi.decode(reason, (string)));
        }
    }

    function bestLiquidity(
        uint256 iters
    ) external returns (uint256 liquidity, uint256 excessiveLiquidity, uint256 newPrice) {
        (liquidity, , ) = IV3AMO(amo).position();
        uint256 liquidityUsed;
        for (uint i; i < iters; i++) {
            (liquidityUsed, excessiveLiquidity, newPrice) = afterUBB(liquidity);
            console.log(liquidityUsed, excessiveLiquidity, newPrice);
            if (excessiveLiquidity == 0 && (FACTOR - newPrice) <= 10) break;
            liquidity = liquidityUsed;
            if (excessiveLiquidity == 0) liquidity += (liquidity * (FACTOR - newPrice)) / FACTOR;
        }
    }
}
