// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StakedFraxLib
 * @dev use the calculation in the sFRAX contract https://etherscan.io/token/0xa663b02cf0a4b149d2ad41910cb81e23e1c41c32
 */
library StakedFraxLib {
    using Math for uint256;

    struct RewardsCycleData {
        uint40 cycleEnd; // Timestamp of the end of the current rewards cycle
        uint40 lastSync; // Timestamp of the last time the rewards cycle was synced
        uint216 rewardCycleAmount; // Amount of rewards to be distributed in the current cycle
    }

    struct StakedFrax {
        uint256 totalSupply; // sFRAX.totalSupply()
        uint256 storedTotalAssets; // sFRAX.storedTotalAssets()
        RewardsCycleData rewardsCycleData; // sFRAX.rewardsCycleData()
        uint256 lastRewardsDistribution; // sFRAX.lastRewardsDistribution()
        uint256 maxDistributionPerSecondPerAsset; // sFRAX.maxDistributionPerSecondPerAsset()
    }

    uint256 private constant PRECISION = 1e18;

    function safeCastTo40(uint256 x) private pure returns (uint40 y) {
        require(x < 1 << 40);
        y = uint40(x);
    }

    /**
     * @notice calculates the amount of rewards to distribute based on the rewards cycle data and the time elapsed
     * @param _rewardsCycleData The rewards cycle data
     * @param _deltaTime The time elapsed since the last rewards distribution
     * @return _rewardToDistribute The amount of rewards to distribute
    */
    function _calculateRewardsToDistribute(
        RewardsCycleData memory _rewardsCycleData,
        uint256 _deltaTime
    ) private pure returns (uint256 _rewardToDistribute) {
        _rewardToDistribute =
            (_rewardsCycleData.rewardCycleAmount * _deltaTime) /
            (_rewardsCycleData.cycleEnd - _rewardsCycleData.lastSync);
    }


    /**
      * @notice calculates the amount of rewards to distribute
    */
    function calculateRewardsToDistribute(
        StakedFrax memory self,
        uint256 _deltaTime
    ) internal pure returns (uint256 _rewardToDistribute) {
        _rewardToDistribute = _calculateRewardsToDistribute(self.rewardsCycleData, _deltaTime);

        // Cap rewards
        uint256 _maxDistribution = (self.maxDistributionPerSecondPerAsset * _deltaTime * self.storedTotalAssets) /
            PRECISION;
        if (_rewardToDistribute > _maxDistribution) {
            _rewardToDistribute = _maxDistribution;
        }
    }

    /**
     * @notice The ```previewDistributeRewards``` function is used to preview the rewards distributed at the top of the block
     * @return _rewardToDistribute The amount of underlying to distribute
    */
    function previewDistributeRewards(StakedFrax memory self) internal view returns (uint256 _rewardToDistribute) {
        // Cache state for gas savings
        RewardsCycleData memory _rewardsCycleData = self.rewardsCycleData;
        uint256 _lastRewardsDistribution = self.lastRewardsDistribution;
        uint40 _timestamp = safeCastTo40(block.timestamp);

        // Calculate the delta time, but only include up to the cycle end in case we are passed it
        uint256 _deltaTime = _timestamp > _rewardsCycleData.cycleEnd
            ? _rewardsCycleData.cycleEnd - _lastRewardsDistribution
            : _timestamp - _lastRewardsDistribution;

        // Calculate the rewards to distribute
        _rewardToDistribute = calculateRewardsToDistribute(self, _deltaTime);
    }

    function totalAssets(StakedFrax memory self) internal view returns (uint256) {
        uint256 _rewardToDistribute = previewDistributeRewards(self);
        return self.storedTotalAssets + _rewardToDistribute;
    }

    function previewRedeem(StakedFrax memory self, uint256 shares) internal view returns (uint256) {
        uint256 supply = self.totalSupply;
        return supply == 0 ? shares : shares.mulDiv(totalAssets(self), supply);
    }

    function previewDeposit(StakedFrax memory self, uint256 assets) internal view returns (uint256) {
        uint256 supply = self.totalSupply;
        return supply == 0 ? assets : assets.mulDiv(supply, totalAssets(self));
    }
}
