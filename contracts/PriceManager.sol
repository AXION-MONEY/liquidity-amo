// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

struct RewardsCycleData {
    uint40 cycleEnd; // Timestamp of the end of the current rewards cycle
    uint40 lastSync; // Timestamp of the last time the rewards cycle was synced
    uint216 rewardCycleAmount; // Amount of rewards to be distributed in the current cycle
}

struct StakedUSDe {
    uint256 totalSupply; // sUSDe.totalSupply()
    uint256 balance; // USDe.balanceOf(sUSDe)
    uint256 lastDistributionTimestamp; // sUSDe.lastDistributionTimestamp()
    uint256 vestingAmount; // sUSDe.vestingAmount()
}

struct StakedFrax {
    uint256 totalSupply; // sFRAX.totalSupply()
    uint256 storedTotalAssets; // sFRAX.storedTotalAssets()
    RewardsCycleData rewardsCycleData; // sFRAX.rewardsCycleData()
    uint256 lastRewardsDistribution; // sFRAX.lastRewardsDistribution()
    uint256 maxDistributionPerSecondPerAsset; // sFRAX.maxDistributionPerSecondPerAsset()
}

library StakedUSDeLib {
    uint256 private constant VESTING_PERIOD = 8 hours;

    function totalAssets(StakedUSDe calldata self) public view returns (uint256) {
        uint256 timeSinceLastDistribution = block.timestamp - self.lastDistributionTimestamp;
        uint256 unvestedAmount = 0;
        if (timeSinceLastDistribution < VESTING_PERIOD) {
            uint256 deltaT = VESTING_PERIOD - timeSinceLastDistribution;
            unvestedAmount = (deltaT * self.vestingAmount) / VESTING_PERIOD;
        }
        return self.balance - unvestedAmount;
    }
}

library StakedFraxLib {
    uint256 private constant PRECISION = 1e18;

    function safeCastTo40(uint256 x) private pure returns (uint40 y) {
        require(x < 1 << 40);
        y = uint40(x);
    }

    function _calculateRewardsToDistribute(
        RewardsCycleData calldata _rewardsCycleData,
        uint256 _deltaTime
    ) private pure returns (uint256 _rewardToDistribute) {
        _rewardToDistribute =
            (_rewardsCycleData.rewardCycleAmount * _deltaTime) /
            (_rewardsCycleData.cycleEnd - _rewardsCycleData.lastSync);
    }

    function calculateRewardsToDistribute(
        StakedFrax calldata self,
        uint256 _deltaTime
    ) public pure returns (uint256 _rewardToDistribute) {
        _rewardToDistribute = _calculateRewardsToDistribute(self.rewardsCycleData, _deltaTime);

        // Cap rewards
        uint256 _maxDistribution = (self.maxDistributionPerSecondPerAsset * _deltaTime * self.storedTotalAssets) /
            PRECISION;
        if (_rewardToDistribute > _maxDistribution) {
            _rewardToDistribute = _maxDistribution;
        }
    }

    function previewDistributeRewards(StakedFrax calldata self) public view returns (uint256 _rewardToDistribute) {
        // Cache state for gas savings
        RewardsCycleData calldata _rewardsCycleData = self.rewardsCycleData;
        uint256 _lastRewardsDistribution = self.lastRewardsDistribution;
        uint40 _timestamp = safeCastTo40(block.timestamp);

        // Calculate the delta time, but only include up to the cycle end in case we are passed it
        uint256 _deltaTime = _timestamp > _rewardsCycleData.cycleEnd
            ? _rewardsCycleData.cycleEnd - _lastRewardsDistribution
            : _timestamp - _lastRewardsDistribution;

        // Calculate the rewards to distribute
        _rewardToDistribute = calculateRewardsToDistribute(self, _deltaTime);
    }

    function totalAssets(StakedFrax calldata self) public view returns (uint256) {
        uint256 _rewardToDistribute = previewDistributeRewards(self);
        return self.storedTotalAssets + _rewardToDistribute;
    }
}

struct Pot {
    uint256 dsr; // the Dai Savings Rate
    uint256 chi; // the Rate Accumulator
    uint256 rho; // time of last drip
}

contract PriceManager is AccessControlEnumerable {
    using Math for uint256;
    using StakedUSDeLib for StakedUSDe;
    using StakedFraxLib for StakedFrax;

    uint256 private constant RAY = 10 ** 27;

    bytes32 public constant SUSDE_SETTER = keccak256("SUSDE_SETTER");
    bytes32 public constant SFRAX_SETTER = keccak256("SFRAX_SETTER");
    bytes32 public constant SDAI_SETTER = keccak256("SDAI_SETTER");

    StakedUSDe public sUSDe;
    StakedFrax public sFRAX;
    Pot public pot;

    uint256 public sUsdeLastSync;
    uint256 public sFraxLastSync;
    uint256 public sDaiLastSync;

    error InvalidLastDistribution();

    constructor(address admin, address setter) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(SUSDE_SETTER, setter);
        _grantRole(SFRAX_SETTER, setter);
        _grantRole(SDAI_SETTER, setter);
    }

    function setSUsde(StakedUSDe calldata _sUSDe) external onlyRole(SUSDE_SETTER) {
        if (_sUSDe.lastDistributionTimestamp > block.timestamp) revert InvalidLastDistribution();
        sUSDe = _sUSDe;
        sUsdeLastSync = block.timestamp;
    }

    function setSFrax(StakedFrax calldata _sFRAX) external onlyRole(SFRAX_SETTER) {
        if (_sFRAX.lastRewardsDistribution > block.timestamp) revert InvalidLastDistribution();
        sFRAX = _sFRAX;
        sFraxLastSync = block.timestamp;
    }

    function setPot(Pot calldata _pot) external onlyRole(SDAI_SETTER) {
        pot = _pot;
        sDaiLastSync = block.timestamp;
    }

    function _rpow(uint256 x, uint256 n) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 {
                    z := RAY
                }
                default {
                    z := 0
                }
            }
            default {
                switch mod(n, 2)
                case 0 {
                    z := RAY
                }
                default {
                    z := x
                }
                let half := div(RAY, 2) // for rounding.
                for {
                    n := div(n, 2)
                } n {
                    n := div(n, 2)
                } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) {
                        revert(0, 0)
                    }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) {
                        revert(0, 0)
                    }
                    x := div(xxRound, RAY)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) {
                            revert(0, 0)
                        }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) {
                            revert(0, 0)
                        }
                        z := div(zxRound, RAY)
                    }
                }
            }
        }
    }

    function sUsdePreviewRedeem(uint256 shares) external view returns (uint256) {
        return shares.mulDiv(sUSDe.totalAssets() + 1, sUSDe.totalSupply + 1);
    }

    function sUsdePreviewDeposit(uint256 assets) external view returns (uint256) {
        return assets.mulDiv(sUSDe.totalSupply + 1, sUSDe.totalAssets() + 1);
    }

    function sFraxPreviewRedeem(uint256 shares) external view returns (uint256) {
        uint256 supply = sFRAX.totalSupply;
        return supply == 0 ? shares : shares.mulDiv(sFRAX.totalAssets(), supply);
    }

    function sFraxPreviewDeposit(uint256 assets) external view returns (uint256) {
        uint256 supply = sFRAX.totalSupply;
        return supply == 0 ? assets : assets.mulDiv(supply, sFRAX.totalAssets());
    }

    function sDaiPreviewRedeem(uint256 shares) external view returns (uint256) {
        uint256 rho = pot.rho;
        uint256 chi = (block.timestamp > rho) ? (_rpow(pot.dsr, block.timestamp - rho) * pot.chi) / RAY : pot.chi;
        return (shares * chi) / RAY;
    }

    function sDaiPreviewDeposit(uint256 assets) external view returns (uint256) {
        uint256 rho = pot.rho;
        uint256 chi = (block.timestamp > rho) ? (_rpow(pot.dsr, block.timestamp - rho) * pot.chi) / RAY : pot.chi;
        return (assets * RAY) / chi;
    }
}
