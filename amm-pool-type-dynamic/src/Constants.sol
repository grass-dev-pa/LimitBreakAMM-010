//SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

/// @dev Minimum tick value for concentrated liquidity positions, equivalent to price of ~1e-38
int24 constant MIN_TICK = -887_272;

/// @dev Maximum tick value for concentrated liquidity positions, equivalent to price of ~1e38
int24 constant MAX_TICK = 887_272;

/// @dev Tick spacing is capped at 16384 to prevent the situation where tickSpacing is so large that
/// @dev _nextInitializedTickWithinOneWord overflows int24 container from a valid tick.
/// @dev 16384 ticks represents a >5x price change with ticks of 1 bips
int24 constant MAX_TICK_SPACING = 16_384;

/// @dev Tick spacing must be at least 1.
int24 constant MIN_TICK_SPACING = 1;

/// @dev The minimum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MIN_TICK)
uint160 constant MIN_SQRT_RATIO = 4_295_128_739;

/// @dev The maximum value that can be returned from #getSqrtPriceAtTick. Equivalent to getSqrtPriceAtTick(MAX_TICK)
uint160 constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

/// @dev The maximum sqrt price minus the minimum sqrt price minus one.
uint160 constant MAX_SQRT_PRICE_MINUS_MIN_SQRT_PRICE_MINUS_ONE = MAX_SQRT_RATIO - MIN_SQRT_RATIO - 1;

/// @dev Max BPS value used in BIPS and fee calculations.
uint256 constant MAX_BPS = 100_00;

/// @dev Q128 fixed-point arithmetic constant (2^128) for high-precision calculations
uint256 constant Q128 = 2 ** 128;

/// @dev Q96 fixed-point arithmetic constant (2^96) for sqrt price representations
uint256 constant Q96 = 2 ** 96;

/// @dev Bit resolution for Q96 fixed-point arithmetic used in price calculations
uint8 constant Q96_RESOLUTION = 96;

/// @dev Bit shift position for pool type address in poolId.
uint8 constant POOL_ID_TYPE_ADDRESS_SHIFT = 144;

/// @dev Bit mask for the creation details hash in poolId.
bytes32 constant POOL_HASH_MASK = 0x0000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF000000000000;

/// @dev Bit shift position for packing pool fee rate in poolId.
uint8 constant POOL_ID_FEE_SHIFT = 0;

/// @dev Bit shift position for packing pool tick spacing in poolId.
uint8 constant POOL_ID_SPACING_SHIFT = 16;