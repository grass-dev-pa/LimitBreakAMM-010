//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity ^0.8.24;

/// @dev Max BPS value used in BIPS and fee calculations.
uint256 constant MAX_BPS = 100_00;

/// @dev Q96 fixed-point arithmetic constant (2^96) for sqrt price representations.
uint256 constant Q96 = 2 ** 96;

/// @dev The minimum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MIN_TICK).
uint160 constant MIN_SQRT_RATIO = 4_295_128_739;

/// @dev The maximum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MAX_TICK).
uint160 constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

/// @dev Bit shift position for pool type address in poolId.
uint8 constant POOL_ID_TYPE_ADDRESS_SHIFT = 144;

/// @dev Bit mask for the creation details hash in poolId.
bytes32 constant POOL_HASH_MASK = 0x0000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF000000000000;

/// @dev Bit shift position for packing pool fee rate in poolId.
uint8 constant POOL_ID_FEE_SHIFT = 0;