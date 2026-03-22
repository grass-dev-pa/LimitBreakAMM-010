//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../Errors.sol";

/**
 * @title SafeCast
 *
 * @notice Provides functions for safely casting between different integer types with overflow protection.
 * @dev    This library ensures safe downcasting operations that would otherwise truncate data or cause
 *         unexpected behavior. Each function validates that the input value fits within the target type's
 *         range before performing the cast, preventing silent overflow/underflow issues.
 */
/// @title Safe casting methods
/// @notice Contains methods for safely casting between types
library SafeCast {

    /// @notice Cast a uint256 to a uint160, revert on overflow
    /// @param x The uint256 to be downcasted
    /// @return y The downcasted integer, now type uint160
    function toUint160(uint256 x) internal pure returns (uint160 y) {
        y = uint160(x);
        if (y != x) revert SafeCast__Uint160Overflow();
    }

    /// @notice Cast a uint256 to a uint128, revert on overflow
    /// @param x The uint256 to be downcasted
    /// @return y The downcasted integer, now type uint128
    function toUint128(uint256 x) internal pure returns (uint128 y) {
        y = uint128(x);
        if (x != y) revert SafeCast__Uint128Overflow();
    }

    /// @notice Cast a int128 to a uint128, revert on overflow or underflow
    /// @param x The int128 to be casted
    /// @return y The casted integer, now type uint128
    function toUint128(int128 x) internal pure returns (uint128 y) {
        if (x < 0) revert SafeCast__Uint128Overflow();
        y = uint128(x);
    }

    /// @notice Cast a int256 to a int128, revert on overflow or underflow
    /// @param x The int256 to be downcasted
    /// @return y The downcasted integer, now type int128
    function toInt128(int256 x) internal pure returns (int128 y) {
        y = int128(x);
        if (y != x) revert SafeCast__Int128Overflow();
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @param x The uint256 to be casted
    /// @return y The casted integer, now type int256
    function toInt256(uint256 x) internal pure returns (int256 y) {
        y = int256(x);
        if (y < 0) revert SafeCast__Uint256ToInt256Overflow();
    }

    /// @notice Cast a uint256 to a int128, revert on overflow
    /// @param x The uint256 to be downcasted
    /// @return The downcasted integer, now type int128
    function toInt128(uint256 x) internal pure returns (int128) {
        if (x >= 1 << 127) revert SafeCast__Uint256ToInt128Overflow();
        return int128(int256(x));
    }
}
