// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Errors.sol";

/// @title Math functions that do not check inputs or outputs
/// @notice Contains methods that perform common math functions but do not do any overflow or underflow checks
library UnsafeMath {
    /**
     * @notice Returns ceil(x / y) with division by zero protection.
     *
     * @dev    Throws when y is zero.
     *
     * @param  x The dividend value.
     * @param  y The divisor value, must be non-zero.
     * @return z The quotient ceiling(x / y).
     */
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (y == 0) {
            revert UnsafeMath__DivisionByZero();
        }
        assembly ("memory-safe") {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }

    /**
     * @notice Calculates floor(a×b÷denominator) with no safety checks.
     *
     * @dev    No overflow or division by zero protection. Caller responsibility.
     *
     * @param  a           The multiplicand value.
     * @param  b           The multiplier value.
     * @param  denominator The divisor value.
     * @return result      The result floor(a×b÷denominator).
     */
    function simpleMulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            result := div(mul(a, b), denominator)
        }
    }
}