//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @dev throws when the value provided to the BitMath library is zero.
error BitMath__ZeroInput();

/// @dev throws when a provided fee rate exceeds the maximum allowed for the operation.
error DynamicPool__InvalidFeeBPS();

/// @dev throws when a liquidity amount change results in invalid amount deltas.
error DynamicPool__InvalidAmountDeltas();

/// @dev throws when a liquidity delta is mismatched with the function being called.
error DynamicPool__InvalidLiquidityChange();

/// @dev throws when the sqrt price is below the minimum or above the maximum.
error DynamicPool__InvalidSqrtPriceX96();

/// @dev throws when the tick is not in alignment with the tick spacing.
error DynamicPool__InvalidTick();

/// @dev throws when the tick spacing is set below the minimum or maximum tick spacing.
error DynamicPool__InvalidTickSpacing();

/// @dev throws when liquidity is higher than max liquidity per tick.
error DynamicPool__LiquidityMustBeLowerThanMaxLiquidityPerTick(uint128 maxLiquidityPerTick);

/// @dev throws when the tick is greater than the maximum tick.
error DynamicPool__MaxTickTooHigh();

/// @dev throws when the ticks are inversed.
error DynamicPool__MinTickMustBeLessThanMaxTick();

/// @dev throws when the tick is lower than the minimum tick.
error DynamicPool__MinTickTooLow();

/// @dev throws when the price of a pool at the start of a swap already exceeds the swap price limit.
error DynamicPool__PoolStartPriceExceedsSwapLimitPrice();

/// @dev throws when a position that does not have liquidity is attempted to be updated.
error DynamicPool__PositionMustHaveLiquidity();

/// @dev throws when a position is adding liquidity with a non-zero snap price and there is active liquidity.
error DynamicPool__PriceCannotSnapWithLiquidity();

/// @dev throws when a price overflow occurs during swap or pool calculations.
error DynamicPool__PriceOverflow();

/// @dev throws when liquidity equals zero.
error SqrtPriceMath__InvalidLiquidity();

/// @dev throws when price equals zero.
error SqrtPriceMath__InvalidPrice();

/// @dev throws when there is insufficient liquidity to complete the requested price movement.
error SqrtPriceMath__NotEnoughLiquidity();