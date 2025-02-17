// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SavingsDaiLib
 * @dev use the calculation in the sDAI contract https://etherscan.io/address/0x83f20f44975d03b1b09e64809b757c47f942beea
 */
library SavingsDaiLib {
    struct Pot {
        uint256 dsr; // the Dai Savings Rate
        uint256 chi; // the Rate Accumulator
        uint256 rho; // time of last drip
    }

    uint256 private constant RAY = 10 ** 27;

    function _rpow(uint256 x, uint256 n) private pure returns (uint256 z) {
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

    function previewRedeem(Pot memory self, uint256 shares) internal view returns (uint256) {
        uint256 rho = self.rho;
        uint256 chi = (block.timestamp > rho) ? (_rpow(self.dsr, block.timestamp - rho) * self.chi) / RAY : self.chi;
        return (shares * chi) / RAY;
    }

    function previewDeposit(Pot memory self, uint256 assets) internal view returns (uint256) {
        uint256 rho = self.rho;
        uint256 chi = (block.timestamp > rho) ? (_rpow(self.dsr, block.timestamp - rho) * self.chi) / RAY : self.chi;
        return (assets * RAY) / chi;
    }
}
