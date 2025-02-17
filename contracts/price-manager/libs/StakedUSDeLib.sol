// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StakedUSDeLib
 * @dev use the calculation in the sUSDC contract https://etherscan.io/address/0x9d39a5de30e57443bff2a8307a4256c8797a3497
 * @dev according to ERC4626
 */
library StakedUSDeLib {
    using Math for uint256;

    struct StakedUSDe {
        uint256 totalSupply; // sUSDe.totalSupply()
        uint256 balance; // USDe.balanceOf(sUSDe)
        uint256 lastDistributionTimestamp; // sUSDe.lastDistributionTimestamp()
        uint256 vestingAmount; // sUSDe.vestingAmount()
    }

    uint256 private constant VESTING_PERIOD = 8 hours;

    /**
     * @dev Returns the total amount of the underlying asset.
     */
    function totalAssets(StakedUSDe memory self) internal view returns (uint256) {
        uint256 timeSinceLastDistribution = block.timestamp - self.lastDistributionTimestamp;
        uint256 unvestedAmount = 0;
        if (timeSinceLastDistribution < VESTING_PERIOD) {
            uint256 deltaT = VESTING_PERIOD - timeSinceLastDistribution;
            unvestedAmount = (deltaT * self.vestingAmount) / VESTING_PERIOD;
        }
        return self.balance - unvestedAmount;
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of assets that would be withdrawn in a redeem call
     *   in the same transaction. I.e. redeem should return the same or more assets as previewRedeem if called in the
     *   same transaction.
     * - MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the
     *   redemption would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by redeeming.
     */
    function previewRedeem(StakedUSDe memory self, uint256 shares) internal view returns (uint256) {
        return shares.mulDiv(totalAssets(self) + 1, self.totalSupply + 1);
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
     * current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of Vault shares that would be minted in a deposit
     *   call in the same transaction. I.e. deposit should return the same or more shares as previewDeposit if called
     *   in the same transaction.
     * - MUST NOT account for deposit limits like those returned from maxDeposit and should always act as though the
     *   deposit would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewDeposit SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewDeposit(StakedUSDe memory self, uint256 assets) internal view returns (uint256) {
        return assets.mulDiv(self.totalSupply + 1, totalAssets(self) + 1);
    }
}
