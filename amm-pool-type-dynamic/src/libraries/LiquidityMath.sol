//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../Errors.sol";

/**
 * @title  LiquidityMath
 * @notice Provides functions for adding and subtracting liquidity with overflow and underflow protection.
 * @dev    This library is used to handle liquidity calculations in the LBAMM protocol. It ensures safe
 *         arithmetic operations when applying signed deltas to unsigned liquidity values, preventing
 *         overflow and underflow conditions that could corrupt liquidity accounting.
 *         
 *         Changes from original Uniswap implementation:
 *         - Updated to solidity 0.8.24
 *         - Added explicit revert messages using custom errors
 *         - Enhanced safety checks for arithmetic operations
 */
library LiquidityMath {
    /**
     * @notice Adds a signed liquidity delta to an existing liquidity amount with overflow/underflow protection.
     *
     * @dev    Throws when the subtraction would result in underflow.
     * @dev    Throws when the addition would result in overflow.
     *
     * @dev    For negative deltas (liquidity removal), the function converts the delta to unsigned and
     *         subtracts it from the original liquidity. For positive deltas (liquidity addition), it
     *         converts the delta to unsigned and adds it to the original liquidity. Both operations
     *         include explicit overflow/underflow checks to ensure safe arithmetic.
     *
     * @param  x The current liquidity amount before applying the change.
     * @param  y The signed delta by which liquidity should be changed (positive for addition, negative for removal).
     * @return z The resulting liquidity amount after applying the delta.
     */
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        assembly ("memory-safe") {
            z := add(and(x, 0xffffffffffffffffffffffffffffffff), signextend(15, y))
            if shr(128, z) {
                // revert SafeCast__Uint128Overflow()
                mstore(0, 0x99efb929)
                revert(0x1c, 0x04)
            }
        }
    }
}
