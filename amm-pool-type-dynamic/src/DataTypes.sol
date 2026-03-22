//SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

/**
 * @notice Top-level storage container for all dynamic pool data.
 * @dev    Contains mappings for pool states, tick bitmaps, tick information, and position data.
 *
 * @param pools            Mapping from pool ID to pool state data
 * @param poolTickBitmap   Mapping from pool ID to tick bitmap for initialized tick tracking
 * @param poolTickInfo     Mapping from tick hash to tick information
 * @param poolPositions    Mapping from position hash to position information
 */
struct DynamicPoolStorage {
    mapping(bytes32 => DynamicPoolState) pools;
    mapping(bytes32 => mapping(int16 => uint256)) poolTickBitmap;
    mapping(bytes32 => TickInfo) poolTickInfo;
    mapping(bytes32 => DynamicPositionInfo) poolPositions;
}

/**
 * @dev    Parameters specific to a dynamic pool creation.
 * @dev    Contains initial configuration values required for deploying a new concentrated liquidity pool.
 * 
 * @param tickSpacing       Tick spacing.
 * @param sqrtPriceRatioX96 Initial price ratio as sqrt(price) * 2^96
 */
struct DynamicPoolCreationDetails {
    int24 tickSpacing;
    uint160 sqrtPriceRatioX96;
}

/**
 * @dev State data for dynamic liquidity pools
 * @dev Contains all state variables for concentrated liquidity pools with tick-based positions
 * 
 * @param feeGrowthGlobal0X128  Global fee growth for token0 as Q128.128 fixed point
 * @param feeGrowthGlobal1X128  Global fee growth for token1 as Q128.128 fixed point
 * @param sqrtPriceX96          Current price as sqrt(price) * 2^96
 * @param tick                  Current tick corresponding to the current price
 * @param liquidity             Total active liquidity in the current price range
 */
struct DynamicPoolState {
    uint256 feeGrowthGlobal0X128;
    uint256 feeGrowthGlobal1X128;
    uint160 sqrtPriceX96;
    int24 tick;
    uint128 liquidity;
}

/**
 * @dev Information stored for each initialized tick in dynamic pools
 * @dev Used for tracking liquidity and fee growth at specific price points
 *
 * @param liquidityGross        Total liquidity referencing this tick
 * @param liquidityNet          Net liquidity change when crossing this tick (can be negative)
 * @param feeGrowthOutside0X128 Fee growth on the opposite side of this tick for token0
 * @param feeGrowthOutside1X128 Fee growth on the opposite side of this tick for token1
 * @param initialized           True if the tick has been initialized (liquidityGross > 0), false otherwise
 */
struct TickInfo {
    uint128 liquidityGross;
    int128 liquidityNet;
    uint256 feeGrowthOutside0X128;
    uint256 feeGrowthOutside1X128;
    bool initialized;
}

/**
 * @dev Position information for dynamic pool liquidity providers
 * @dev Tracks concentrated liquidity positions within specific tick ranges
 * 
 * @param liquidity                Amount of liquidity provided by this position
 * @param feeGrowthInside0LastX128 Last recorded fee growth inside the position's range for token0
 * @param feeGrowthInside1LastX128 Last recorded fee growth inside the position's range for token1
 */
struct DynamicPositionInfo {
    uint128 liquidity;
    uint256 feeGrowthInside0LastX128;
    uint256 feeGrowthInside1LastX128;
}

/**
 * @dev Parameters for modifying dynamic pool liquidity
 * @dev Used when adding or removing liquidity from concentrated liquidity positions
 * @dev When `snapSqrtPriceX96` is non-zero, the active tick and all ticks to the snap price **must** have zero liquidity.
 * 
 * @param tickLower         Lower bound of the liquidity range
 * @param tickUpper         Upper bound of the liquidity range
 * @param liquidityChange   Amount of liquidity to add (positive) or remove (negative)
 * @param snapSqrtPriceX96  Price to move to prior to adding liquidity.
 */
struct DynamicLiquidityModificationParams {
    int24 tickLower;
    int24 tickUpper;
    int128 liquidityChange;
    uint160 snapSqrtPriceX96;
}

/**
 * @dev Parameters for collecting dynamic pool fees
 * @dev Used when collecting fees from concentrated liquidity positions
 * 
 * @param tickLower         Lower bound of the liquidity range
 * @param tickUpper         Upper bound of the liquidity range
 */
struct DynamicLiquidityCollectFeesParams {
    int24 tickLower;
    int24 tickUpper;
}

/**
 * @dev Internal cache for dynamic liquidity modifications
 * @dev Used internally to avoid stack too deep errors during liquidity operations
 * 
 * @param poolId                The pool being liquidity is being modified on
 * @param tickLowerHash         Hash key for lower tick: keccak256(abi.encodePacked(poolId, tickLower))
 * @param tickUpperHash         Hash key for upper tick: keccak256(abi.encodePacked(poolId, tickUpper))
 * @param flippedLower          Whether the lower tick was flipped (crossed) during this operation
 * @param flippedUpper          Whether the upper tick was flipped (crossed) during this operation
 * @param feeGrowthInside0X128  Fee growth inside the position's tick range for token0
 * @param feeGrowthInside1X128  Fee growth inside the position's tick range for token1
 * @param amount0               Calculated amount of token0 for this liquidity change
 * @param amount1               Calculated amount of token1 for this liquidity change
 * @param tokensOwed0           Amount of token0 fees owed to the position
 * @param tokensOwed1           Amount of token1 fees owed to the position
 */
struct ModifyDynamicLiquidityCache {
    bytes32 poolId;
    bytes32 tickLowerHash;
    bytes32 tickUpperHash;
    bool flippedLower;
    bool flippedUpper;
    uint256 feeGrowthInside0X128;
    uint256 feeGrowthInside1X128;
    int256 amount0;
    int256 amount1;
    uint256 tokensOwed0;
    uint256 tokensOwed1;
}

/**
 * @notice Cache structure for dynamic pool swap state during execution.
 * @dev    Used internally to track swap progress and avoid stack too deep errors.
 *
 * @param poolId                   The pool being swapped in
 * @param zeroForOne               Direction of swap (token0 for token1 if true, false otherwise)
 * @param liquidity                Current active liquidity
 * @param tick                     Current tick position
 * @param amountSpecified          Amount to consume in the swap
 * @param amountSpecifiedRemaining Amount left to consume in the swap
 * @param amountCalculated         Amount calculated so far
 * @param protocolFeeBPS           Protocol fee rate in basis points
 * @param protocolFee              Protocol fee amount accumulated
 * @param feeAmount                Total fee amount for this swap
 * @param feeGrowthGlobalX128      Global fee growth tracker
 * @param sqrtPriceLimitX96        Price limit for the swap
 * @param sqrtPriceCurrentX96      Current price during swap execution
 */
struct DynamicSwapCache {
    bytes32 poolId;
    bool zeroForOne;
    uint128 liquidity;
    int24 tick;
    uint256 amountSpecified;
    uint256 amountSpecifiedRemaining;
    uint256 amountCalculated;
    uint256 protocolFeeBPS;
    uint256 protocolFee;
    uint256 feeAmount;
    uint256 feeGrowthGlobalX128;
    uint160 sqrtPriceLimitX96;
    uint160 sqrtPriceCurrentX96;
}

/**
 * @dev Intermediate calculations for dynamic pool swap steps
 * @dev Used internally during swap execution to track step-by-step computations
 * 
 * @param sqrtPriceStartX96 Starting price for this swap step
 * @param tickNext          Next tick boundary to be crossed
 * @param initialized       Whether the next tick is initialized
 * @param sqrtPriceNextX96  Price at the next tick boundary
 * @param amountIn          Amount of input token consumed in this step
 * @param amountOut         Amount of output token produced in this step
 * @param feeAmount         Fee amount collected in this step
 */
struct StepComputations {
    uint160 sqrtPriceStartX96;
    int24 tickNext;
    bool initialized;
    uint160 sqrtPriceNextX96;
    uint256 amountIn;
    uint256 amountOut;
    uint256 feeAmount;
}