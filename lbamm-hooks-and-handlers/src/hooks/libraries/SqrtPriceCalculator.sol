//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title  SqrtPriceCalculator
 * @notice Library to compute the sqrt price ratio given two amounts of tokens.
 */
library SqrtPriceCalculator {
    /// @dev The minimum value that can be returned from _computeRatioX96.
    uint160 constant MIN_SQRT_RATIO = 4_295_128_739;

    /// @dev The maximum value that can be returned from _computeRatioX96.
    uint160 constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    /**
     * @notice Computes the square root price ratio in Q64.96 format from token amounts.
     *
     * @dev    Throws when the computed ratio would overflow the uint160 return type.
     *
     * @dev    This function calculates sqrt(amount1/amount0) * 2^96, handling edge cases where either amount
     *         is zero. It uses dynamic scaling to prevent overflow during intermediate calculations and employs
     *         an optimized square root algorithm for efficiency.
     *
     * @param  amount1   The amount of token1 used to compute the ratio.
     * @param  amount0   The amount of token0 used to compute the ratio.
     * @return ratioX96  The square root price ratio in Q64.96 format, or 0 if overflow occurs.
     */
    function computeRatioX96(uint256 amount1, uint256 amount0) internal pure returns (uint160 ratioX96) {
        if (amount1 == 0 && amount0 == 0) {
            return 2 ** 96;
        }
        if (amount1 == 0) {
            return MIN_SQRT_RATIO;
        }
        if (amount0 == 0) {
            return MAX_SQRT_RATIO;
        }

        uint256 maxMultiplier = type(uint256).max / amount1;
        uint256 multiplier;
        uint256 n = 96;
        while (true) {
            multiplier = 2 ** (n << 1);
            if (maxMultiplier >= multiplier) break;
            if (n == 0) break;
            --n;
        }

        unchecked {
            uint256 tmpRatio = _sqrt(amount1 * multiplier / amount0) * (2 ** (96 - n));
            if (tmpRatio > type(uint160).max) {
                return 0;
            }
            ratioX96 = uint160(tmpRatio);
        }
    }

    /**
     * @notice Computes the integer square root of a number using the Babylonian method.
     *
     * @dev    This function implements an optimized square root algorithm using assembly for gas efficiency.
     *         It uses the Babylonian method with a good initial estimate to converge quickly to the correct result.
     *         The algorithm guarantees that the result is floor(sqrt(x)).
     *
     * @param  x The number to compute the square root of.
     * @return z The integer square root of x, rounded down.
     */
    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // `floor(sqrt(2**15)) = 181`. `sqrt(2**15) - 181 = 2.84`.
            z := 181 // The "correct" value is 1, but this saves a multiplication later.

            // This segment is to get a reasonable initial estimate for the Babylonian method. With a bad
            // start, the correct # of bits increases ~linearly each iteration instead of ~quadratically.

            // Let `y = x / 2**r`. We check `y >= 2**(k + 8)`
            // but shift right by `k` bits to ensure that if `x >= 256`, then `y >= 256`.
            let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffffff, shr(r, x))))
            z := shl(shr(1, r), z)

            // Goal was to get `z*z*y` within a small factor of `x`. More iterations could
            // get y in a tighter range. Currently, we will have y in `[256, 256*(2**16))`.
            // We ensured `y >= 256` so that the relative difference between `y` and `y+1` is small.
            // That's not possible if `x < 256` but we can just verify those cases exhaustively.

            // Now, `z*z*y <= x < z*z*(y+1)`, and `y <= 2**(16+8)`, and either `y >= 256`, or `x < 256`.
            // Correctness can be checked exhaustively for `x < 256`, so we assume `y >= 256`.
            // Then `z*sqrt(y)` is within `sqrt(257)/sqrt(256)` of `sqrt(x)`, or about 20bps.

            // For `s` in the range `[1/256, 256]`, the estimate `f(s) = (181/1024) * (s+1)`
            // is in the range `(1/2.84 * sqrt(s), 2.84 * sqrt(s))`,
            // with largest error when `s = 1` and when `s = 256` or `1/256`.

            // Since `y` is in `[256, 256*(2**16))`, let `a = y/65536`, so that `a` is in `[1/256, 256)`.
            // Then we can estimate `sqrt(y)` using
            // `sqrt(65536) * 181/1024 * (a + 1) = 181/4 * (y + 65536)/65536 = 181 * (y + 65536)/2**18`.

            // There is no overflow risk here since `y < 2**136` after the first branch above.
            z := shr(18, mul(z, add(shr(r, x), 65536))) // A `mul()` is saved from starting `z` at 181.

            // Given the worst case multiplicative error of 2.84 above, 7 iterations should be enough.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // If `x+1` is a perfect square, the Babylonian method cycles between
            // `floor(sqrt(x))` and `ceil(sqrt(x))`. This statement ensures we return floor.
            // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
            z := sub(z, lt(div(x, z), z))
        }
    }
}