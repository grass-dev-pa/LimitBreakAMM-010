//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../Constants.sol";
import "../Errors.sol";

import "@limitbreak/tm-core-lib/src/utils/misc/SafeCast.sol";
import "@limitbreak/tm-core-lib/src/utils/math/FullMath.sol";
import "@limitbreak/tm-core-lib/src/utils/math/UnsafeMath.sol";

/**
 * @title  SqrtPriceMath
 * @notice Contains mathematical functions that use square root prices in Q64.96 format and liquidity to compute token amount deltas.
 * @dev    All functions are based on Q64.96 square root price representation and liquidity values. This library provides
 *         the core mathematical operations for AMM price calculations, including price movements based on token swaps
 *         and liquidity position calculations. The Q64.96 format provides high precision for price calculations while
 *         maintaining computational efficiency.
 */
library SqrtPriceMath {
    using SafeCast for uint256;

    /**
     * @notice Calculates the next square root price given an input amount.
     *
     * @dev    Throws when the starting price is zero.
     * @dev    Throws when the liquidity is zero.
     * @dev    Throws when the calculated next price is out of valid bounds.
     *
     * @dev    This function determines the new price after a swap where a specific amount of tokens is being
     *         provided as input. The calculation uses different rounding strategies depending on the swap direction
     *         to ensure conservative price movements that favor the pool.
     *
     * @param  sqrtPX96   The starting square root price in Q64.96 format before accounting for the input amount.
     * @param  liquidity  The amount of usable liquidity available for the swap.
     * @param  amountIn   The amount of token0 or token1 being swapped in.
     * @param  zeroForOne True if token0 is being swapped for token1, false for the reverse.
     * @return sqrtQX96   The square root price in Q64.96 format after adding the input amount.
     */
    function getNextSqrtPriceFromInput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        if (sqrtPX96 == 0) {
            revert SqrtPriceMath__InvalidPrice();
        }
        if (liquidity == 0) {
            revert SqrtPriceMath__InvalidLiquidity();
        }

        // round to make sure that we don't pass the target price
        return zeroForOne
            ? _getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountIn, true)
            : _getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountIn, true);
    }

    /**
     * @notice Calculates the next square root price given an output amount.
     *
     * @dev    Throws when the starting price is zero.
     * @dev    Throws when the liquidity is zero.
     * @dev    Throws when the calculated next price is out of valid bounds.
     *
     * @dev    This function determines the new price after a swap where a specific amount of tokens is being
     *         withdrawn as output. The calculation uses different rounding strategies depending on the swap direction
     *         to ensure the pool receives at least the required input amount.
     *
     * @param  sqrtPX96   The starting square root price in Q64.96 format before accounting for the output amount.
     * @param  liquidity  The amount of usable liquidity available for the swap.
     * @param  amountOut  The amount of token0 or token1 being swapped out.
     * @param  zeroForOne True if token0 is being swapped for token1, false for the reverse.
     * @return sqrtQX96   The square root price in Q64.96 format after removing the output amount.
     */
    function getNextSqrtPriceFromOutput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        if (sqrtPX96 == 0) {
            revert SqrtPriceMath__InvalidPrice();
        }
        if (liquidity == 0) {
            revert SqrtPriceMath__InvalidLiquidity();
        }

        // round to make sure that we pass the target price
        return zeroForOne
            ? _getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountOut, false)
            : _getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountOut, false);
    }

    /**
     * @notice Calculates the amount of token0 required to cover a liquidity position between two prices.
     *
     * @dev    Throws when the lower price is zero.
     *
     * @dev    This function computes liquidity / sqrt(lower) - liquidity / sqrt(upper), which is mathematically
     *         equivalent to liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower)).
     *         The calculation maintains precision using Q96 scaling factors.
     *
     * @param  sqrtRatioAX96 A square root price in Q64.96 format.
     * @param  sqrtRatioBX96 Another square root price in Q64.96 format.
     * @param  liquidity     The amount of usable liquidity for the position.
     * @param  roundUp       Whether to round the calculated amount up or down.
     * @return amount0       The amount of token0 required for the liquidity position between the two prices.
     */
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        if (sqrtRatioAX96 == 0) {
            revert SqrtPriceMath__InvalidPrice();
        }

        // Multiply the liquidity by Q96 to maintain precision
        uint256 numerator1 = uint256(liquidity) << Q96_RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        return roundUp
            ? UnsafeMath.divRoundingUp(
                // ((L * Q96) * (sqrtRatioBX96 - sqrtRatioAX96)) / sqrtRatioBX96
                FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                // (((L * Q96) * (sqrtRatioBX96 - sqrtRatioAX96)) / sqrtRatioBX96) / sqrtRatioAX96
                // Logical equivalent to
                // (L * Q96) * (sqrtRatioBX96 - sqrtRatioAX96) / (sqrtRatioBX96 * sqrtRatioAX96)
                sqrtRatioAX96
            )
            : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }

    /// @notice Equivalent to: `a >= b ? a - b : b - a`
    function absDiff(uint160 a, uint160 b) internal pure returns (uint256 res) {
        assembly ("memory-safe") {
            let diff :=
                sub(and(a, 0xffffffffffffffffffffffffffffffffffffffff), and(b, 0xffffffffffffffffffffffffffffffffffffffff))
            // mask = 0 if a >= b else -1 (all 1s)
            let mask := sar(255, diff)
            // if a >= b, res = a - b = 0 ^ (a - b)
            // if a < b, res = b - a = ~~(b - a) = ~(-(b - a) - 1) = ~(a - b - 1) = (-1) ^ (a - b - 1)
            // either way, res = mask ^ (a - b + mask)
            res := xor(mask, add(mask, diff))
        }
    }

    /**
     * @notice Calculates the amount of token1 required to cover a liquidity position between two prices.
     *
     * @dev    This function computes liquidity * (sqrt(upper) - sqrt(lower)) using high-precision arithmetic
     *         with proper scaling by Q96 factors. The calculation is simpler than token0 since it doesn't
     *         involve division by square root terms.
     *
     * @param  sqrtPriceAX96 A square root price in Q64.96 format.
     * @param  sqrtPriceBX96 Another square root price in Q64.96 format.
     * @param  liquidity     The amount of usable liquidity for the position.
     * @param  roundUp       Whether to round the calculated amount up or down.
     * @return amount1       The amount of token1 required for the liquidity position between the two prices.
     */
    function getAmount1Delta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        uint256 numerator = absDiff(sqrtPriceAX96, sqrtPriceBX96);
        uint256 denominator = Q96;
        uint256 _liquidity = uint256(liquidity);

        amount1 = FullMath.mulDiv(_liquidity, numerator, denominator);
        assembly ("memory-safe") {
            amount1 := add(amount1, and(gt(mulmod(_liquidity, numerator, denominator), 0), roundUp))
        }
    }

    /**
     * @notice Calculates the signed token0 delta for a given liquidity change between two prices.
     *
     * @dev    This helper function handles both positive and negative liquidity changes, returning a signed
     *         result. For negative liquidity (position removal), it rounds down to favor the pool. For positive
     *         liquidity (position addition), it rounds up to ensure sufficient token amounts.
     *
     * @param  sqrtPriceAX96 A square root price in Q64.96 format.
     * @param  sqrtPriceBX96 Another square root price in Q64.96 format.
     * @param  liquidity     The signed change in liquidity for which to compute the token0 delta.
     * @return amount0       The signed amount of token0 corresponding to the liquidity change.
     */
    function getAmount0Delta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        int128 liquidity
    ) internal pure returns (int256 amount0) {
        unchecked {
            return liquidity < 0
                ? -getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, uint128(-liquidity), false).toInt256()
                : getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, uint128(liquidity), true).toInt256();
        }
    }

    /**
     * @notice Calculates the signed token1 delta for a given liquidity change between two prices.
     *
     * @dev    This helper function handles both positive and negative liquidity changes, returning a signed
     *         result. For negative liquidity (position removal), it rounds down to favor the pool. For positive
     *         liquidity (position addition), it rounds up to ensure sufficient token amounts.
     *
     * @param  sqrtPriceAX96 A square root price in Q64.96 format.
     * @param  sqrtPriceBX96 Another square root price in Q64.96 format.
     * @param  liquidity     The signed change in liquidity for which to compute the token1 delta.
     * @return amount1       The signed amount of token1 corresponding to the liquidity change.
     */
    function getAmount1Delta(
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        int128 liquidity
    ) internal pure returns (int256 amount1) {
        unchecked {
            return liquidity < 0
                ? -getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, uint128(-liquidity), false).toInt256()
                : getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, uint128(liquidity), true).toInt256();
        }
    }

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

    /**
     * @notice Calculates the next square root price given a delta of token0.
     *
     * @dev    Throws when there is insufficient liquidity for the operation.
     * @dev    Throws when overflow occurs during intermediate calculations.
     *
     * @dev    Always rounds up because in output-based cases (increasing price) the price must move far enough
     *         to provide the desired output amount, and in input-based cases (decreasing price) the price should
     *         move conservatively to avoid sending excess output.
     *
     *         Uses the formula: liquidity * sqrtPX96 / (liquidity +- amount * sqrtPX96)
     *         If overflow occurs, falls back to: liquidity / (liquidity / sqrtPX96 +- amount)
     *
     * @param  sqrtPX96  The starting square root price in Q64.96 format.
     * @param  liquidity The amount of usable liquidity.
     * @param  amount    The amount of token0 to add or remove from virtual reserves.
     * @param  add       True to add the amount, false to remove it.
     * @return           The new square root price after applying the token0 delta.
     */
    function _getNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        // we short circuit amount == 0 because the result is otherwise not guaranteed to equal the input price
        if (amount == 0) return sqrtPX96;
        uint256 numerator1 = uint256(liquidity) << Q96_RESOLUTION;

        if (add) {
            unchecked {
                uint256 product = amount * sqrtPX96;
                if (product / amount == sqrtPX96) {
                    uint256 denominator = numerator1 + product;
                    if (denominator >= numerator1) {
                        // always fits in 160 bits
                        return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
                    }
                }
            }
            // denominator is checked for overflow
            return uint160(UnsafeMath.divRoundingUp(numerator1, (numerator1 / sqrtPX96) + amount));
        } else {
            unchecked {
                uint256 product = amount * sqrtPX96;
                // if the product overflows, we know the denominator underflows
                // in addition, we must check that the denominator does not underflow
                // equivalent: if (product / amount != sqrtPX96 || numerator1 <= product) revert DynamicPool__PriceOverflow();
                assembly ("memory-safe") {
                    if iszero(
                        and(
                            eq(div(product, amount), and(sqrtPX96, 0xffffffffffffffffffffffffffffffffffffffff)),
                            gt(numerator1, product)
                        )
                    ) {
                        mstore(0, 0x5e429be6) // selector for DynamicPool__PriceOverflow()
                        revert(0x1c, 0x04)
                    }
                }
                uint256 denominator = numerator1 - product;
                return FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator).toUint160();
            }
        }
    }

    /**
     * @notice Calculates the next square root price given a delta of token1.
     *
     * @dev    Throws when there is insufficient liquidity for the subtraction operation.
     *
     * @dev    Always rounds down because in output-based cases (decreasing price) the price must move far enough
     *         to provide the desired output amount, and in input-based cases (increasing price) the price should
     *         move conservatively to avoid sending excess output.
     *
     *         Uses the formula: sqrtPX96 +- amount / liquidity
     *
     * @param  sqrtPX96  The starting square root price in Q64.96 format.
     * @param  liquidity The amount of usable liquidity.
     * @param  amount    The amount of token1 to add or remove from virtual reserves.
     * @param  add       True to add the amount, false to remove it.
     * @return           The new square root price after applying the token1 delta.
     */
    function _getNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        // if we're adding (subtracting), rounding down requires rounding the quotient down (up)
        // in both cases, avoid a mulDiv for most inputs
        if (add) {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? (amount << Q96_RESOLUTION) / liquidity
                    : FullMath.mulDiv(amount, Q96, liquidity)
            );

            return (uint256(sqrtPX96) + quotient).toUint160();
        } else {
            uint256 quotient = (
                amount <= type(uint160).max
                    ? UnsafeMath.divRoundingUp(amount << Q96_RESOLUTION, liquidity)
                    : FullMath.mulDivRoundingUp(amount, Q96, liquidity)
            );

            if (sqrtPX96 <= quotient) {
                revert SqrtPriceMath__NotEnoughLiquidity();
            }
            // always fits 160 bits
            unchecked {
                return uint160(sqrtPX96 - quotient);
            }
        }
    }
}
