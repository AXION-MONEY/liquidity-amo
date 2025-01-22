// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

library StakedUSDeLib {
    using Math for uint256;

    struct StakedUSDe {
        uint256 totalSupply; // sUSDe.totalSupply()
        uint256 balance; // USDe.balanceOf(sUSDe)
        uint256 lastDistributionTimestamp; // sUSDe.lastDistributionTimestamp()
        uint256 vestingAmount; // sUSDe.vestingAmount()
    }

    uint256 private constant VESTING_PERIOD = 8 hours;

    function totalAssets(StakedUSDe memory self) internal view returns (uint256) {
        uint256 timeSinceLastDistribution = block.timestamp - self.lastDistributionTimestamp;
        uint256 unvestedAmount = 0;
        if (timeSinceLastDistribution < VESTING_PERIOD) {
            uint256 deltaT = VESTING_PERIOD - timeSinceLastDistribution;
            unvestedAmount = (deltaT * self.vestingAmount) / VESTING_PERIOD;
        }
        return self.balance - unvestedAmount;
    }

    function previewRedeem(StakedUSDe memory self, uint256 shares) internal view returns (uint256) {
        return shares.mulDiv(totalAssets(self) + 1, self.totalSupply + 1);
    }

    function previewDeposit(StakedUSDe memory self, uint256 assets) internal view returns (uint256) {
        return assets.mulDiv(self.totalSupply + 1, totalAssets(self) + 1);
    }
}
