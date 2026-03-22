//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/// @dev The minimum value that can be set for a price.
uint160 constant MIN_SQRT_RATIO = 4_295_128_739;

/// @dev The maximum value that can be set for a price.
uint160 constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

/// @dev Q96 fixed-point arithmetic constant (2^96) for sqrt price representations.
uint256 constant Q96 = 2 ** 96;

/// @dev The maximum value that a group key's scale can be to avoid overflow.
uint8 constant MAXIMUM_ORDER_SCALE = 72;