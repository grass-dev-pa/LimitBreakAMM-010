//SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import "./LiquidityMath.sol";

import "./DynamicPoolDecoder.sol";
import "./SqrtPriceMath.sol";
import "./TickMath.sol";
import "./SwapMath.sol";

import "../DataTypes.sol";
import "../Errors.sol";

import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";
import "@limitbreak/tm-core-lib/src/utils/misc/SafeCast.sol";

/**
 * @title  DynamicHelper
 * @author Limit Break, Inc.
 * @notice Provides utilities for managing dynamic liquidity positions, tick operations, and position calculations in the LBAMM system.
 *
 * @dev    This library contains the core logic for concentrated liquidity management including position modifications,
 *         tick bitmap operations, fee calculations, and validation functions. It implements the mathematical and storage
 *         operations necessary for concentrated liquidity pools within the Limit Break AMM framework.
 */
library DynamicHelper {
    using SafeCast for uint256;
    using SafeCast for int256;

    /**
     * @notice Modifies a dynamic liquidity position by adding or removing liquidity within a specified tick range.
     *
     * @dev    Throws when tick parameters are invalid or out of bounds.
     * @dev    Throws when liquidity operations would exceed maximum liquidity per tick.
     * @dev    Throws when there is insufficient liquidity for removal operations.
     *
     * @dev    This function handles the complete process of modifying a concentrated liquidity position including:
     *         tick updates, bitmap flipping, fee calculations, and position state management. It calculates the
     *         required token amounts based on the current price relative to the position's tick range.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Tick information has been updated for both tickLower and tickUpper.
     * @dev    2. Tick bitmaps have been flipped if ticks were initialized or deinitialized.
     * @dev    3. Position liquidity and fee growth tracking have been updated.
     * @dev    4. Pool liquidity has been updated if the position is currently active.
     * @dev    5. Unused tick info has been deleted for removed liquidity positions.
     * @dev    6. Token amounts required for the position change have been calculated and stored.
     *
     * @param  liquidityCache Cache structure for storing intermediate calculation results.
     * @param  position       Storage reference to the position being modified.
     * @param  tickLower      The lower tick boundary of the position.
     * @param  tickUpper      The upper tick boundary of the position.
     * @param  liquidityChange The signed amount of liquidity to add (positive) or remove (negative).
     */
    function modifyPosition(
        ModifyDynamicLiquidityCache memory liquidityCache,
        DynamicPoolStorage storage ammState,
        DynamicPositionInfo storage position,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityChange
    ) internal {
        liquidityCache.tickLowerHash = EfficientHash.efficientHash(liquidityCache.poolId, bytes32(uint256(int256(tickLower))));
        liquidityCache.tickUpperHash = EfficientHash.efficientHash(liquidityCache.poolId, bytes32(uint256(int256(tickUpper))));
        DynamicPoolState memory poolState = ammState.pools[liquidityCache.poolId];

        {
            TickInfo storage tickInfoLower = ammState.poolTickInfo[liquidityCache.tickLowerHash];
            TickInfo storage tickInfoUpper = ammState.poolTickInfo[liquidityCache.tickUpperHash];
            uint128 maxLiquidityPerTick = _poolMaxLiquidityPerTick(liquidityCache.poolId);

            liquidityCache.flippedLower = _updateTick(
                tickInfoLower,
                tickLower,
                poolState.tick,
                liquidityChange,
                poolState.feeGrowthGlobal0X128,
                poolState.feeGrowthGlobal1X128,
                false,
                maxLiquidityPerTick
            );
            liquidityCache.flippedUpper = _updateTick(
                tickInfoUpper,
                tickUpper,
                poolState.tick,
                liquidityChange,
                poolState.feeGrowthGlobal0X128,
                poolState.feeGrowthGlobal1X128,
                true,
                maxLiquidityPerTick
            );

            (liquidityCache.feeGrowthInside0X128, liquidityCache.feeGrowthInside1X128) = _getFeeGrowthInside(
                tickInfoLower,
                tickInfoUpper,
                tickLower,
                tickUpper,
                poolState.tick,
                poolState.feeGrowthGlobal0X128,
                poolState.feeGrowthGlobal1X128
            );
        }

        if (liquidityCache.flippedLower) {
            _flipTick(
                ammState.poolTickBitmap[liquidityCache.poolId], tickLower, DynamicPoolDecoder.getPoolTickSpacing(liquidityCache.poolId)
            );
        }
        if (liquidityCache.flippedUpper) {
            _flipTick(
                ammState.poolTickBitmap[liquidityCache.poolId], tickUpper, DynamicPoolDecoder.getPoolTickSpacing(liquidityCache.poolId)
            );
        }

        _updatePosition(
            liquidityCache,
            position,
            liquidityChange,
            liquidityCache.feeGrowthInside0X128,
            liquidityCache.feeGrowthInside1X128
        );

        if (liquidityChange < 0) {
            if (liquidityCache.flippedLower) {
                delete ammState.poolTickInfo[liquidityCache.tickLowerHash];
            }
            if (liquidityCache.flippedUpper) {
                delete ammState.poolTickInfo[liquidityCache.tickUpperHash];
            }
        }

        // There are 3 cases we need to take into consideration:
        // 1. The current tick is below the passed range (currentTick < tickLower)
        // 2. The current tick is within the passed range (tickLower <= currentTick <= tickUpper)
        // 3. The current tick is above the passed range (currentTick > tickUpper)
        if (poolState.tick < tickLower) {
            // 1. The current tick is below the passed range (currentTick < tickLower)
            // In this case, all liquidity added would be in token0, so we only need to calculate the amount of token0
            // owed.
            liquidityCache.amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidityChange
            );
        } else if (poolState.tick < tickUpper) {
            // 2. The current tick is within the passed range (tickLower <= currentTick <= tickUpper)
            // In this case, we need to calculate the amount of token0 and token1 owed.
            // We can calculate the amount of token0 owed by calculating the amount of token0 owed between the current
            // tick and the upper tick, and the amount of token1 owed by calculating the amount of token1 owed between
            // the lower tick and the current tick.
            // Finally, we need to update the liquidity of the pool, as the liquidity is active.
            liquidityCache.amount0 = SqrtPriceMath.getAmount0Delta(
                poolState.sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickUpper), liquidityChange
            );
            liquidityCache.amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtPriceAtTick(tickLower), poolState.sqrtPriceX96, liquidityChange
            );


            ammState.pools[liquidityCache.poolId].liquidity =
                LiquidityMath.addDelta(poolState.liquidity, liquidityChange);
        } else {
            // 3. The current tick is above the passed range (currentTick > tickUpper)
            // In this case, all liquidity added would be in token1, so we only need to calculate the amount of token1
            // owed.
            liquidityCache.amount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidityChange
            );
        }
    }

    /**
     * @notice Collects accumulated fees for a liquidity position without modifying liquidity amounts.
     *
     * @dev    This function calculates and updates the fees owed to a position by determining the
     *         fee growth within the position's tick range and updating the position's fee tracking.
     *         No liquidity is added or removed during this operation.
     *
     *         <h4>Postconditions:</h4>
     *         1. Fee growth inside the position's range has been calculated
     *         2. Position's fee tracking has been updated to current values
     *         3. Accumulated fee amounts have been calculated and stored in cache
     *
     * @param  liquidityCache Cache structure for storing calculated fee amounts.
     * @param  ammState       Pool storage containing tick and position data.
     * @param  position       Storage reference to the position collecting fees.
     * @param  poolId         The identifier of the pool containing the position.
     * @param  tickLower      The lower tick boundary of the position.
     * @param  tickUpper      The upper tick boundary of the position.
     */
    function collectFees(
        ModifyDynamicLiquidityCache memory liquidityCache,
        DynamicPoolStorage storage ammState,
        DynamicPositionInfo storage position,
        bytes32 poolId,
        int24 tickLower,
        int24 tickUpper
    ) internal {
        DynamicPoolState storage poolState = ammState.pools[poolId];
        liquidityCache.tickLowerHash = EfficientHash.efficientHash(poolId, bytes32(uint256(int256(tickLower))));
        liquidityCache.tickUpperHash = EfficientHash.efficientHash(poolId, bytes32(uint256(int256(tickUpper))));

        {
            TickInfo storage tickInfoLower = ammState.poolTickInfo[liquidityCache.tickLowerHash];
            TickInfo storage tickInfoUpper = ammState.poolTickInfo[liquidityCache.tickUpperHash];

            (liquidityCache.feeGrowthInside0X128, liquidityCache.feeGrowthInside1X128) = _getFeeGrowthInside(
                tickInfoLower,
                tickInfoUpper,
                tickLower,
                tickUpper,
                poolState.tick,
                poolState.feeGrowthGlobal0X128,
                poolState.feeGrowthGlobal1X128
            );
        }

        _updatePosition(
            liquidityCache,
            position,
            0,
            liquidityCache.feeGrowthInside0X128,
            liquidityCache.feeGrowthInside1X128
        );
    }

    /**
     * @notice Moves the pool's current price to the snap price.
     *
     * @dev    Throws when there is active liquidity between the current price and the snap price.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Pool price has been moved to the snap price.
     *
     * @param  ammState          Storage pointer to the AMM state.
     * @param  poolId            The identifier of the pool to snap price on.
     * @param  snapSqrtPriceX96  The price to move the pool to.
     */
    function snapPrice(
        DynamicPoolStorage storage ammState,
        bytes32 poolId,
        uint160 snapSqrtPriceX96
    ) internal {
        DynamicPoolState storage poolState = ammState.pools[poolId];

        // Check for active liquidity at current price
        if (poolState.liquidity > 0) {
            revert DynamicPool__PriceCannotSnapWithLiquidity();
        }

        int24 currentTick = poolState.tick;
        int24 targetTick = TickMath.getTickAtSqrtPrice(snapSqrtPriceX96);

        // If ticks are equal we are moving price within the tick and have already checked liquidity
        if (currentTick != targetTick) {
            bool lte = targetTick < currentTick;
            mapping(int16 => uint256) storage poolTickBitmap = ammState.poolTickBitmap[poolId];
            int24 tickSpacing = DynamicPoolDecoder.getPoolTickSpacing(poolId);

            while (true) {
                (int24 next, bool initialized) = _nextInitializedTickWithinOneWord(poolTickBitmap, currentTick, tickSpacing, lte);

                if (initialized) {
                    // Next tick is initialized, check if there is liquidity before the target
                    if (lte) {
                        if (next > targetTick) {
                            revert DynamicPool__PriceCannotSnapWithLiquidity();
                        }
                    } else {
                        if (next <= targetTick) {
                            revert DynamicPool__PriceCannotSnapWithLiquidity();
                        }
                    }
                } else {
                    // Next tick is not initialized, check if we have passed the target
                    if (lte) {
                        if (next <= targetTick) {
                            break;
                        }
                    } else {
                        if (next > targetTick) {
                            break;
                        }
                    }
                }

                currentTick = lte ? next - 1 : next;
            }
        }

        poolState.sqrtPriceX96 = snapSqrtPriceX96;
        poolState.tick = targetTick;
    }

    /**
     * @notice Computes a single swap step for input-based swaps within a price range.
     *
     * @param  swapCache    Swap state cache to update with step results.
     * @param  step         Step computation results containing amounts and fees.
     * @param  poolFeeBPS   Pool fee rate in basis points.
     */
    function _swapByInputStep(
        DynamicSwapCache memory swapCache,
        StepComputations memory step,
        uint16 poolFeeBPS
    ) internal pure {
        SwapMath.computeSwapByInputStep(swapCache, step, poolFeeBPS);
        swapCache.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount);
        swapCache.amountCalculated = swapCache.amountCalculated + step.amountOut;
    }

    /**
     * @notice Computes a single swap step for output-based swaps within a price range.
     *
     * @param  swapCache    Swap state cache to update with step results.
     * @param  step         Step computation results containing amounts and fees.
     * @param  poolFeeBPS   Pool fee rate in basis points.
     */
    function _swapByOutputStep(
        DynamicSwapCache memory swapCache,
        StepComputations memory step,
        uint16 poolFeeBPS
    ) internal pure {
        SwapMath.computeSwapByOutputStep(swapCache, step, poolFeeBPS);
        swapCache.amountSpecifiedRemaining -= step.amountOut;
        swapCache.amountCalculated = swapCache.amountCalculated + (step.amountIn + step.feeAmount);
    }

    /**
     * @notice Executes a concentrated liquidity swap by iterating through price ranges until completion.
     *
     * @dev    Throws when there is insufficient liquidity for the specified swap amount.
     *
     *         Implements the core swap logic for concentrated liquidity pools by stepping through
     *         initialized ticks, computing swap amounts within each price range, and updating
     *         pool state. Uses the provided swap step function to handle input-based vs output-based logic.
     *
     *         <h4>Postconditions:</h4>
     *         1. Swap cache updated with final amounts and remaining liquidity
     *         2. Pool tick bitmap traversed to find liquidity within price ranges
     *         3. Tick crossings executed with liquidity net updates applied
     *         4. Protocol fees calculated and accumulated in swap cache
     *         5. Pool fee growth updated based on fees collected during swap
     *         6. Final tick and sqrt price updated in swap cache
     *
     * @param  ammState     Pool storage containing tick and bitmap data.
     * @param  swapCache    Swap state cache for tracking progress and calculations.
     * @param  poolState    Current pool state with price and liquidity information.
     * @param  poolFeeBPS   Pool fee rate in basis points.
     * @param  _swapStep    Function pointer for input-based or output-based step logic.
     */
    function computeSwap(
        DynamicPoolStorage storage ammState,
        DynamicSwapCache memory swapCache,
        DynamicPoolState memory poolState,
        uint16 poolFeeBPS,
        function (DynamicSwapCache memory, StepComputations memory, uint16) _swapStep
    ) internal {
        if (swapCache.zeroForOne) {
            if (swapCache.sqrtPriceLimitX96 >= swapCache.sqrtPriceCurrentX96 || swapCache.sqrtPriceLimitX96 <= MIN_SQRT_RATIO) {
                revert DynamicPool__PoolStartPriceExceedsSwapLimitPrice();
            }
        } else {
            if (swapCache.sqrtPriceLimitX96 <= swapCache.sqrtPriceCurrentX96 || swapCache.sqrtPriceLimitX96 >= MAX_SQRT_RATIO) {
                revert DynamicPool__PoolStartPriceExceedsSwapLimitPrice();
            }
        }
        
        StepComputations memory step;

        while (
            swapCache.amountSpecifiedRemaining != 0 && swapCache.sqrtPriceCurrentX96 != swapCache.sqrtPriceLimitX96
        ) {
            step.sqrtPriceStartX96 = swapCache.sqrtPriceCurrentX96;

            (step.tickNext, step.initialized) = _nextInitializedTickWithinOneWord(
                ammState.poolTickBitmap[swapCache.poolId],
                swapCache.tick,
                DynamicPoolDecoder.getPoolTickSpacing(swapCache.poolId),
                swapCache.zeroForOne
            );

            if (step.tickNext < MIN_TICK) {
                step.tickNext = MIN_TICK;
            } else if (step.tickNext > MAX_TICK) {
                step.tickNext = MAX_TICK;
            }

            uint160 nextTickSqrtPriceX96 = TickMath.getSqrtPriceAtTick(step.tickNext);
            uint160 sqrtPriceLimitX96 = swapCache.sqrtPriceLimitX96;
            step.sqrtPriceNextX96 = (
                swapCache.zeroForOne ? nextTickSqrtPriceX96 < sqrtPriceLimitX96 : nextTickSqrtPriceX96 > sqrtPriceLimitX96
            ) ? sqrtPriceLimitX96 : nextTickSqrtPriceX96;
            
            // compute values to swap to the target tick, price limit, or point where input/output amount is exhausted
            _swapStep(swapCache, step, poolFeeBPS);

            if (swapCache.protocolFeeBPS > 0) {
                uint256 delta = FullMath.mulDivRoundingUp(step.feeAmount, swapCache.protocolFeeBPS, MAX_BPS);
                step.feeAmount -= delta;
                swapCache.protocolFee += delta;
            }

            swapCache.feeAmount = swapCache.feeAmount + step.feeAmount;

            if (swapCache.liquidity > 0) {
                unchecked {
                    swapCache.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, Q128, swapCache.liquidity);
                }
            }

            // shift tick if we reached the next price
            if (swapCache.sqrtPriceCurrentX96 == nextTickSqrtPriceX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    int128 liquidityNet = _crossTick(
                        ammState.poolTickInfo[EfficientHash.efficientHash(
                            swapCache.poolId, bytes32(uint256(int256(step.tickNext)))
                        )],
                        (swapCache.zeroForOne ? swapCache.feeGrowthGlobalX128 : poolState.feeGrowthGlobal0X128),
                        (swapCache.zeroForOne ? poolState.feeGrowthGlobal1X128 : swapCache.feeGrowthGlobalX128)
                    );
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    if (swapCache.zeroForOne) liquidityNet = -liquidityNet;
                    swapCache.liquidity = LiquidityMath.addDelta(swapCache.liquidity, liquidityNet);
                }

                swapCache.tick = swapCache.zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (swapCache.sqrtPriceCurrentX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                swapCache.tick = TickMath.getTickAtSqrtPrice(swapCache.sqrtPriceCurrentX96);
            }
        }
    }

    /**
     * @notice Returns the next initialized tick within one 256-bit word of the tick bitmap.
     *
     * @dev    This function efficiently finds the next tick with liquidity in the direction of the swap
     *         by examining the tick bitmap. It uses bit manipulation to quickly locate initialized ticks
     *         without iterating through every possible tick position.
     *
     * @param  poolTickBitmap_ The storage mapping containing the pool's tick bitmap.
     * @param  tick            The current tick from which to search.
     * @param  tickSpacing     The tick spacing of the pool determining valid tick positions.
     * @param  lte             Whether to search for ticks less than or equal to the current tick.
     * @return next            The next initialized tick in the specified direction.
     * @return initialized     Whether an initialized tick was found within the current word.
     */
    function _nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage poolTickBitmap_,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        unchecked {
            int24 compressed = tick / tickSpacing;
            if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

            if (lte) {
                (int16 wordPos, uint8 bitPos) = _bitmapPosition(compressed);
                // all the 1s at or to the right of the current bitPos
                uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
                uint256 masked = poolTickBitmap_[wordPos] & mask;

                // if there are no initialized ticks to the right of or at the current tick, return rightmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                next = initialized
                    ? (compressed - int24(int256(uint256(bitPos) - uint256(BitMath.mostSignificantBit(masked))))) * tickSpacing
                    : (compressed - int24(int256(uint256(bitPos)))) * tickSpacing;
            } else {
                // start from the word of the next tick, since the current tick state doesn't matter
                (int16 wordPos, uint8 bitPos) = _bitmapPosition(compressed + 1);
                // all the 1s at or to the left of the bitPos
                uint256 mask = ~((1 << bitPos) - 1);
                uint256 masked = poolTickBitmap_[wordPos] & mask;

                // if there are no initialized ticks to the left of the current tick, return leftmost in the word
                initialized = masked != 0;
                // overflow/underflow is possible, but prevented externally by limiting both tickSpacing and tick
                next = initialized
                    ? (compressed + 1 + int24(int256(uint256(BitMath.leastSignificantBit(masked) - bitPos)))) * tickSpacing
                    : (compressed + 1 + int24(int256(uint256(type(uint8).max - bitPos)))) * tickSpacing;
            }
        }
    }

    /**
     * @notice Updates tick information when crossing during a swap and returns the net liquidity change.
     *
     * @dev    When a swap crosses a tick boundary, this function updates the fee growth tracking for the tick
     *         and returns the net liquidity change that should be applied to the pool's active liquidity.
     *
     *         <h4>Postconditions:</h4>
     *         1. Tick's fee growth outside values have been updated to reflect the crossing.
     *
     * @param  poolTickInfo_        Storage reference to the tick information being crossed.
     * @param  feeGrowthGlobal0X128 The current global fee growth for token0.
     * @param  feeGrowthGlobal1X128 The current global fee growth for token1.
     * @return liquidityNet         The net liquidity change to apply when crossing this tick.
     */
    function _crossTick(TickInfo storage poolTickInfo_, uint256 feeGrowthGlobal0X128, uint256 feeGrowthGlobal1X128)
        internal
        returns (int128 liquidityNet)
    {
        unchecked {
            poolTickInfo_.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - poolTickInfo_.feeGrowthOutside0X128;
            poolTickInfo_.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - poolTickInfo_.feeGrowthOutside1X128;
        }
        liquidityNet = poolTickInfo_.liquidityNet;
    }

    /**
     * @notice Computes the position in the tick bitmap where the initialized bit for a tick lives.
     *
     * @dev    This function calculates both the word position (which 256-bit word in the mapping) and the bit
     *         position within that word for a given tick. Uses bit operations for efficient computation.
     *
     * @param  tick    The tick for which to compute the bitmap position.
     * @return wordPos The key in the mapping containing the word where the bit is stored.
     * @return bitPos  The bit position within the word where the tick's initialized flag is stored.
     */
    function _bitmapPosition(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        unchecked {
            wordPos = int16(tick >> 8);
            bitPos = uint8(uint256(int256(tick)) % 256);
        }
    }

    /**
     * @notice Validates that the provided tick range is valid for liquidity operations.
     *
     * @dev    Throws when the lower tick is greater than or equal to the upper tick.
     * @dev    Throws when the lower tick is below the minimum allowed tick.
     * @dev    Throws when the upper tick is above the maximum allowed tick.
     *
     * @dev    This function ensures that tick parameters meet the basic requirements for concentrated liquidity
     *         positions including proper ordering and boundary constraints.
     *
     * @param  tickLower The lower tick boundary to validate.
     * @param  tickUpper The upper tick boundary to validate.
     */
    function requireValidTicks(int24 tickLower, int24 tickUpper) internal pure {
        if (tickLower >= tickUpper) {
            revert DynamicPool__MinTickMustBeLessThanMaxTick();
        }
        if (tickLower < MIN_TICK) {
            revert DynamicPool__MinTickTooLow();
        }
        if (tickUpper > MAX_TICK) {
            revert DynamicPool__MaxTickTooHigh();
        }
    }

    /**
     * @notice Calculates the tokens owed to a position based on fee growth since the last update.
     *
     * @dev    This function computes accumulated fees by calculating the difference between current fee growth
     *         and the position's last recorded fee growth, then multiplying by the position's liquidity.
     *         Uses Q128 fixed-point arithmetic for precision.
     *
     * @param  positionCache         The position data containing liquidity and last fee growth values.
     * @param  feeGrowthInside0X128  The current fee growth inside the position's range for token0.
     * @param  feeGrowthInside1X128  The current fee growth inside the position's range for token1.
     * @return tokensOwed0           The amount of token0 fees owed to the position.
     * @return tokensOwed1           The amount of token1 fees owed to the position.
     */
    function _getTokensOwed(DynamicPositionInfo memory positionCache, uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
        internal
        pure
        returns (uint128 tokensOwed0, uint128 tokensOwed1)
    {
        uint256 delta0;
        uint256 delta1;
        unchecked {
            delta0 = feeGrowthInside0X128 - positionCache.feeGrowthInside0LastX128;
            delta1 = feeGrowthInside1X128 - positionCache.feeGrowthInside1LastX128;
        }
        tokensOwed0 = uint128(FullMath.mulDiv(delta0, positionCache.liquidity, Q128));
        tokensOwed1 = uint128(FullMath.mulDiv(delta1, positionCache.liquidity, Q128));
    }

    /**
     * @notice Calculates the fee growth inside a tick range based on the current tick position.
     *
     * @dev    This function implements the complex logic for determining fee growth within a specific tick range
     *         by considering whether the current tick is below, within, or above the range. The calculation uses
     *         the fee growth values stored outside each tick boundary.
     *
     * @param  lower                The tick info for the lower boundary.
     * @param  upper                The tick info for the upper boundary.
     * @param  tickLower            The lower tick value.
     * @param  tickUpper            The upper tick value.
     * @param  tickCurrent          The current active tick in the pool.
     * @param  feeGrowthGlobal0X128 The global accumulated fee growth for token0.
     * @param  feeGrowthGlobal1X128 The global accumulated fee growth for token1.
     * @return feeGrowthInside0X128 The fee growth inside the tick range for token0.
     * @return feeGrowthInside1X128 The fee growth inside the tick range for token1.
     */
    function _getFeeGrowthInside(
        TickInfo storage lower,
        TickInfo storage upper,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        unchecked {
            if (tickCurrent < tickLower) {
                // If the current tick is lower than the lower tick, the fee growth inside is the difference between the
                // the lower and upper tick. This is due to the fact that the lower tick would have more fee growth than
                // the upper tick, as it has most recently accrued fees.
                feeGrowthInside0X128 = lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 = lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            } else if (tickCurrent >= tickUpper) {
                // If the current tick is greater than or equal to the upper tick, the fee growth inside is the difference
                // between the upper and lower tick. This is due to the fact that the upper tick would have more fee growth
                // than the lower tick, as it has most recently accrued fees.
                feeGrowthInside0X128 = upper.feeGrowthOutside0X128 - lower.feeGrowthOutside0X128;
                feeGrowthInside1X128 = upper.feeGrowthOutside1X128 - lower.feeGrowthOutside1X128;
            } else {
                // If the current tick is between the lower and upper tick, the fee growth inside is the difference between
                // the global fee growth and the fee growth outside the lower and upper tick.
                feeGrowthInside0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            }
        }
    }

    /**
     * @notice Calculates the maximum liquidity that can be allocated to a single tick in a pool.
     *
     * @dev    This function determines the maximum liquidity per tick by dividing the maximum possible uint128
     *         value by the total number of initializable ticks in the pool. This prevents liquidity concentration
     *         that could cause overflow in calculations.
     *
     * @param  poolId                The identifier of the pool to calculate the limit for.
     * @return maxLiquidityPerTick   The maximum amount of liquidity that can be assigned to any single tick.
     */
    function _poolMaxLiquidityPerTick(bytes32 poolId) internal pure returns (uint128 maxLiquidityPerTick) {
        unchecked {
            int24 tickSpacing = DynamicPoolDecoder.getPoolTickSpacing(poolId);
            int24 minTick = (MIN_TICK / tickSpacing) * tickSpacing;
            int24 maxTick = (MAX_TICK / tickSpacing) * tickSpacing;
            uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;

            return type(uint128).max / numTicks;
        }
    }

    /**
     * @notice Flips the initialization bit for a specific tick in the pool's tick bitmap.
     *
     * @dev    Throws when the tick is not aligned with the pool's tick spacing.
     *
     * @dev    This function toggles the bit representing whether a tick is initialized (has liquidity).
     *         It first validates that the tick is properly aligned with the pool's tick spacing, then
     *         calculates the bitmap position and performs the XOR operation to flip the bit.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. The initialization bit for the specified tick has been flipped in the bitmap.
     * @dev    2. The tick's alignment with tick spacing has been validated.
     *
     * @param  poolTickBitmap_ The storage mapping containing the pool's tick bitmap.
     * @param  tick            The tick whose initialization bit should be flipped.
     * @param  tickSpacing     The tick spacing requirement for the pool.
     */
    function _flipTick(mapping(int16 => uint256) storage poolTickBitmap_, int24 tick, int24 tickSpacing) internal {
        if (tick % tickSpacing != 0) {
            revert DynamicPool__InvalidTick();
        }
        tick = tick / tickSpacing;

        int16 wordPos;
        uint8 bitPos;
        unchecked{
            wordPos = int16(tick >> 8);
            bitPos = uint8(uint256(int256(tick)) % 256);  
        }

        uint256 mask = 1 << bitPos;
        poolTickBitmap_[wordPos] ^= mask;
    }

    /**
     * @notice Updates a position's state including liquidity and fee growth tracking.
     *
     * @dev    Throws when attempting to operate on a position with zero liquidity when no liquidity change is specified.
     *
     * @dev    This function handles position updates by calculating accumulated fees, updating liquidity amounts,
     *         and refreshing fee growth tracking. It ensures proper fee collection and liquidity accounting.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Accumulated fees have been calculated and stored in the liquidity cache.
     * @dev    2. Position liquidity has been updated if a liquidity change was specified.
     * @dev    3. Position fee growth tracking has been updated to current values.
     *
     * @param  liquidityCache       Cache structure for storing calculated fee amounts.
     * @param  position             Storage reference to the position being updated.
     * @param  liquidityChange      The change in liquidity (0 for fee collection only).
     * @param  feeGrowthInside0X128 The current fee growth inside the position's range for token0.
     * @param  feeGrowthInside1X128 The current fee growth inside the position's range for token1.
     */
    function _updatePosition(
        ModifyDynamicLiquidityCache memory liquidityCache,
        DynamicPositionInfo storage position,
        int128 liquidityChange,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        DynamicPositionInfo memory positionCache = position;

        if (liquidityChange == 0) {
            if (positionCache.liquidity == 0) {
                revert DynamicPool__PositionMustHaveLiquidity();
            }
        } else {
            position.liquidity = LiquidityMath.addDelta(positionCache.liquidity, liquidityChange);
        }

        // Accumulated fees are calculated by multiplying the difference between the current fee growth and the last fee
        // growth by the liquidity, and then dividing by Q128.
        (liquidityCache.tokensOwed0, liquidityCache.tokensOwed1) =
            _getTokensOwed(positionCache, feeGrowthInside0X128, feeGrowthInside1X128);

        position.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1X128;
    }

    /**
     * @notice Updates tick information when liquidity is added or removed at a specific tick.
     *
     * @dev    Throws when the resulting liquidity would exceed the maximum liquidity per tick.
     *
     * @dev    This function manages tick state including gross/net liquidity, initialization status, and fee growth
     *         tracking. It determines whether a tick should be flipped (initialized/deinitialized) based on
     *         liquidity changes and handles fee growth initialization for new ticks.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Tick's gross liquidity has been updated with the liquidity change.
     * @dev    2. Tick's net liquidity has been updated based on whether it's an upper or lower boundary.
     * @dev    3. If the tick was newly initialized, its fee growth outside values have been set.
     * @dev    4. The tick's initialization status has been updated if necessary.
     *
     * @param  tickInfo              Storage reference to the tick being updated.
     * @param  tick                  The tick value being updated.
     * @param  tickCurrent           The current active tick in the pool.
     * @param  liquidityChange       The signed change in liquidity at this tick.
     * @param  feeGrowthGlobal0X128  The global fee growth for token0.
     * @param  feeGrowthGlobal1X128  The global fee growth for token1.
     * @param  upper                 Whether this tick serves as an upper boundary for positions.
     * @param  maxLiquidity          The maximum liquidity allowed per tick.
     * @return flipped               Whether the tick's initialization state was flipped.
     */
    function _updateTick(
        TickInfo storage tickInfo,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityChange,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped) {
        uint128 liquidityGrossBefore = tickInfo.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityChange);

        if (liquidityGrossAfter > maxLiquidity) {
            revert DynamicPool__LiquidityMustBeLowerThanMaxLiquidityPerTick(maxLiquidity);
        }

        // There are 2 cases where we need to flip the tick:
        // 1. The tick had no liquidity and now has liquidity.
        // 2. The tick had liquidity and now has no liquidity.
        // This equation will check both cases and return true if the tick was flipped.
        flipped = (liquidityGrossBefore == 0) != (liquidityGrossAfter == 0);

        // Initialize the tick if liquidity was added
        if (liquidityGrossBefore == 0) {
            // by convention, we assume that all growth before a tick was initialized happened _below_ the tick
            if (tick <= tickCurrent) {
                tickInfo.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                tickInfo.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }
            tickInfo.initialized = true;
        }

        tickInfo.liquidityGross = liquidityGrossAfter;

        tickInfo.liquidityNet = upper
            ? (int256(tickInfo.liquidityNet) - liquidityChange).toInt128()
            : (int256(tickInfo.liquidityNet) + liquidityChange).toInt128();
    }
}
