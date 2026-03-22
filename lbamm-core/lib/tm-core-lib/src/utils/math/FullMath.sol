//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../Errors.sol";

/**
 * @title FullMath
 *
 * @notice Facilitates multiplication and division that can have overflow of an intermediate value without any loss of precision.
 * @dev    Handles "phantom overflow" where intermediate calculations exceed 256 bits but the final result fits in uint256.
 *         This library is essential for high-precision mathematical operations in AMM calculations where maintaining
 *         accuracy is critical for proper pricing and fee calculations.
 */
library FullMath {
    /**
     * @notice Calculates floor(a×b÷denominator) with full precision and phantom overflow protection.
     *
     * @dev    Throws when the result overflows a uint256.
     * @dev    Throws when the denominator is zero.
     *
     * @dev    This function uses a sophisticated algorithm that performs 512-bit multiplication followed by
     *         256-bit division to avoid precision loss. The algorithm handles cases where a×b would overflow
     *         uint256 but the final result a×b÷denominator fits within uint256.
     *
     *         The implementation uses the Chinese Remainder Theorem to reconstruct the 512-bit product,
     *         then performs exact division using modular arithmetic and Newton-Raphson iteration for
     *         computing the modular inverse.
     *
     * @dev    Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
     *
     * @param  a           The multiplicand in the calculation.
     * @param  b           The multiplier in the calculation.
     * @param  denominator The divisor in the calculation, must be greater than 0.
     * @return result      The 256-bit result of floor(a × b ÷ denominator).
     */
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = a * b
            // Compute the product mod 2**256 and mod 2**256 - 1
            // then use the Chinese Remainder Theorem to reconstruct
            // the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2**256 + prod0
            uint256 prod0 = a * b; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly ("memory-safe") {
                let mm := mulmod(a, b, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Make sure the result is less than 2**256.
            // Also prevents denominator == 0
            if (denominator <= prod1) {
                revert FullMath__MulDivOverflowError();
            }

            // Handle non-overflow cases, 256 by 256 division
            if (prod1 == 0) {
                assembly ("memory-safe") {
                    result := div(prod0, denominator)
                }
                return result;
            }

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0]
            // Compute remainder using mulmod
            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(a, b, denominator)
            }
            // Subtract 256 bit number from 512 bit number
            assembly ("memory-safe") {
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator
            // Compute largest power of two divisor of denominator.
            // Always >= 1.
            uint256 twos = (0 - denominator) & denominator;
            // Divide denominator by power of two
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
            }

            // Divide [prod1 prod0] by the factors of two
            assembly ("memory-safe") {
                prod0 := div(prod0, twos)
            }
            // Shift in bits from prod1 into prod0. For this we need
            // to flip `twos` such that it is 2**256 / twos.
            // If twos is zero, then it becomes one
            assembly ("memory-safe") {
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            // Invert denominator mod 2**256
            // Now that denominator is an odd number, it has an inverse
            // modulo 2**256 such that denominator * inv = 1 mod 2**256.
            // Compute the inverse by starting with a seed that is correct
            // correct for four bits. That is, denominator * inv = 1 mod 2**4
            uint256 inv = (3 * denominator) ^ 2;
            // Now use Newton-Raphson iteration to improve the precision.
            // Thanks to Hensel's lifting lemma, this also works in modular
            // arithmetic, doubling the correct bits in each step.
            inv *= 2 - denominator * inv; // inverse mod 2**8
            inv *= 2 - denominator * inv; // inverse mod 2**16
            inv *= 2 - denominator * inv; // inverse mod 2**32
            inv *= 2 - denominator * inv; // inverse mod 2**64
            inv *= 2 - denominator * inv; // inverse mod 2**128
            inv *= 2 - denominator * inv; // inverse mod 2**256

            // Because the division is now exact we can divide by multiplying
            // with the modular inverse of denominator. This will give us the
            // correct result modulo 2**256. Since the preconditions guarantee
            // that the outcome is less than 2**256, this is the final result.
            // We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inv;
            return result;
        }
    }

    /**
     * @notice Calculates ceil(a×b÷denominator) with full precision and phantom overflow protection.
     *
     * @dev    Throws when the result overflows a uint256.
     * @dev    Throws when the denominator is zero.
     * @dev    Throws when the ceiling calculation causes overflow.
     *
     * @dev    This function performs the same high-precision multiplication and division as mulDiv,
     *         but rounds the result up to the next integer if there is any remainder. It first
     *         calculates the floor value using mulDiv, then checks for a remainder and increments
     *         if necessary.
     *
     * @param  a           The multiplicand in the calculation.
     * @param  b           The multiplier in the calculation.
     * @param  denominator The divisor in the calculation, must be greater than 0.
     * @return result      The 256-bit result of ceil(a × b ÷ denominator).
     */
    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            result = mulDiv(a, b, denominator);
            if (mulmod(a, b, denominator) != 0) {
                if (++result == 0) {
                    revert FullMath__MulDivOverflowError();
                }
            }
        }
    }
}
