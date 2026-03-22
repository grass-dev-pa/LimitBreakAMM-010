//SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import "./Constants.sol";
import "./interfaces/IDynamicPoolType.sol";
import "./libraries/DynamicHelper.sol";
import "./libraries/TickMath.sol";

import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";
import "@limitbreak/tm-core-lib/src/utils/misc/StaticDelegateCall.sol";

/**
 * @title  DynamicPoolType
 * @notice Concentrated liquidity AMM pool implementation designed for multi-AMM contract support.
 * @dev    Implements concentrated liquidity with tick-based position management,
 *         fee growth tracking, and optimized swap execution. Supports arbitrary tick spacing and
 *         provides precise liquidity management through mathematical tick boundaries. This contract is designed to 
 *         be used via external call to provide a dynamic pool invariant to AMM contracts who manage reserves.
 *
 * @dev    **Key Features:**
 *         - Concentrated liquidity positions with custom tick ranges
 *         - Gas-optimized swap execution with tick traversal
 *         - Fee growth tracking with Q128.128 fixed-point precision
 *         - Position-specific fee collection without liquidity modification
 *         - Deterministic pool ID generation with bit-packed parameters
 *         - Handles logic for dynamic liquidity pools, relies on AMM for reserve management
 */
contract DynamicPoolType is IDynamicPoolType, StaticDelegateCall {
    /**
     * @notice Global storage mapping from AMM contract addresses to their pool data, specific to concentrated liquidity
     *         pools.
     * @dev    Each AMM contract maintains isolated pool state through this mapping structure.
     *         Provides access to pool states, tick bitmaps, tick information, and position data.
     */
    mapping (address => DynamicPoolStorage) internal globalState;

    constructor() { }

    /**
     * @notice Creates a new concentrated liquidity pool with specified tick spacing and initial price.
     *
     * @dev    Throws when poolParams cannot be decoded as DynamicPoolCreationDetails.
     * @dev    Throws when initial price is outside valid bounds.
     * @dev    Throws when tick spacing exceeds MIN/MAX limits.
     *
     *         Validates parameters, generates deterministic pool ID, and initializes pool state with zero liquidity and
     *         fees. Returns pool ID for AMM to manage corresponding reserves.
     *
     *         <h4>Postconditions</h4>
     *         1. The pool ID is generated and returned to the caller.
     *
     * @param  poolCreationDetails Standard pool creation parameters including pool type, LP fee, tokens, poolHook and encoded tick spacing and initial price.
     * @return poolId              Deterministic identifier for the created pool.
     */
    function createPool(
        PoolCreationDetails calldata poolCreationDetails
    ) external returns (bytes32 poolId) {
        DynamicPoolCreationDetails memory dynamicPoolDetails = abi.decode(poolCreationDetails.poolParams, (DynamicPoolCreationDetails));
        if (dynamicPoolDetails.sqrtPriceRatioX96 < MIN_SQRT_RATIO || dynamicPoolDetails.sqrtPriceRatioX96 >= MAX_SQRT_RATIO) {
            revert DynamicPool__InvalidSqrtPriceX96();
        }

        if (dynamicPoolDetails.tickSpacing > MAX_TICK_SPACING) {
            revert DynamicPool__InvalidTickSpacing();
        } else if (dynamicPoolDetails.tickSpacing < MIN_TICK_SPACING) {
            revert DynamicPool__InvalidTickSpacing();
        }

        poolId = _generatePoolId(poolCreationDetails, dynamicPoolDetails);

        globalState[msg.sender].pools[poolId] = DynamicPoolState({
            feeGrowthGlobal0X128: 0,
            feeGrowthGlobal1X128: 0,
            sqrtPriceX96: dynamicPoolDetails.sqrtPriceRatioX96,
            tick: TickMath.getTickAtSqrtPrice(dynamicPoolDetails.sqrtPriceRatioX96),
            liquidity: 0
        });
    }

    /**
     * @notice Computes the deterministic pool ID that would be generated for given parameters.
     *
     * @dev    Throws when poolParams cannot be decoded as DynamicPoolCreationDetails.
     *
     * @param  poolCreationDetails Standard pool creation parameters including encoded tick spacing and initial price.
     * @return poolId              Deterministic identifier that would be generated for these parameters.
     */
    function computePoolId(
        PoolCreationDetails calldata poolCreationDetails
    ) external view returns (bytes32 poolId) {
        DynamicPoolCreationDetails memory dynamicPoolDetails = abi.decode(poolCreationDetails.poolParams, (DynamicPoolCreationDetails));

        poolId = _generatePoolId(poolCreationDetails, dynamicPoolDetails);
    }

    /**
     * @notice Generates deterministic pool ID from creation parameters with bit-packed data.
     *
     * @dev    Expects dynamicPoolDetails to be properly decoded from poolCreationDetails.poolParams.
     *         Two-phase generation: First creates a hash from all parameters, then overlays bit-packed data for
     *         efficient parameter extraction.
     *         
     *         Hash includes all pool-defining parameters for uniqueness. Bit-packing enables
     *         parameter extraction without additional storage. Uses POOL_HASH_MASK to clear
     *         reserved bits before overlaying packed parameter data.
     *
     * @param  poolCreationDetails Standard pool creation parameters (tokens, fees, hook).
     * @param  dynamicPoolDetails  Dynamic-specific parameters (tick spacing, initial price).
     * @return poolId              Deterministic pool identifier with extractable data.
     */
    function _generatePoolId(
        PoolCreationDetails calldata poolCreationDetails,
        DynamicPoolCreationDetails memory dynamicPoolDetails
    ) internal view returns (bytes32 poolId) {
        poolId = EfficientHash.efficientHash(
            bytes32(uint256(uint160(address(this)))),
            bytes32(uint256(poolCreationDetails.fee)),
            bytes32(uint256(int256(dynamicPoolDetails.tickSpacing))),
            bytes32(uint256(uint160(poolCreationDetails.token0))),
            bytes32(uint256(uint160(poolCreationDetails.token1))),
            bytes32(uint256(uint160(poolCreationDetails.poolHook)))
        ) & POOL_HASH_MASK;

        poolId = poolId | 
            bytes32((uint256(uint160(address(this))) << POOL_ID_TYPE_ADDRESS_SHIFT)) |
            bytes32(uint256(poolCreationDetails.fee) << POOL_ID_FEE_SHIFT) | 
            bytes32(uint256(uint24(dynamicPoolDetails.tickSpacing)) << POOL_ID_SPACING_SHIFT);
    }

    /**
     * @notice Collects accrued fees from a concentrated liquidity position without modifying liquidity.
     *
     * @dev    Throws when poolParams cannot be decoded as DynamicLiquidityCollectFeesParams.
     * @dev    Throws when tickLower >= tickUpper.
     * @dev    Throws when tickUpper > MAX_TICK.
     * @dev    Throws when tickLower < MIN_TICK.
     *     
     * @dev    Calculates and collects fees based on position's tick range and fee growth since last collection.
     *         Returns collected amounts for AMM to handle actual token transfers.
     *
     *         <h4>Postconditions</h4>
     *         1. The collected fee amounts are returned to the caller.
     *
     * @param  poolId              Pool identifier for fee collection.
     * @param  ammBasePositionId   Base position identifier from AMM contract.
     * @param  poolParams          Encoded DynamicLiquidityCollectFeesParams with tick range.
     * @return positionId          Deterministic position identifier.
     * @return fees0               Collected fees in token0.
     * @return fees1               Collected fees in token1.
     */
    function collectFees(
        bytes32 poolId,
        address,
        bytes32 ammBasePositionId,
        bytes calldata poolParams
    ) external returns (
        bytes32 positionId,
        uint256 fees0,
        uint256 fees1
    ) {
        DynamicPoolStorage storage ammState = globalState[msg.sender];
        DynamicLiquidityCollectFeesParams memory liquidityParams = abi.decode(poolParams, (DynamicLiquidityCollectFeesParams));
        DynamicHelper.requireValidTicks(liquidityParams.tickLower, liquidityParams.tickUpper);

        positionId = EfficientHash.efficientHash(
            ammBasePositionId,
            bytes32(uint256(uint24(liquidityParams.tickLower))),
            bytes32(uint256(uint24(liquidityParams.tickUpper)))
        );

        DynamicPositionInfo storage position = ammState.poolPositions[positionId];

        ModifyDynamicLiquidityCache memory liquidityCache;

        DynamicHelper.collectFees(
            liquidityCache,
            ammState,
            position,
            poolId,
            liquidityParams.tickLower,
            liquidityParams.tickUpper
        );

        fees0 = liquidityCache.tokensOwed0;
        fees1 = liquidityCache.tokensOwed1;
    }

    /**
     * @notice Adds concentrated liquidity to a position within specified tick range.
     *
     * @dev    Throws when poolParams cannot be decoded as DynamicLiquidityModificationParams.
     * @dev    Throws when tickLower >= tickUpper.
     * @dev    Throws when tickUpper > MAX_TICK.
     * @dev    Throws when tickLower < MIN_TICK.
     * @dev    Throws when ticks are not aligned with tick spacing.
     * @dev    Throws when liquidityChange is negative.
     * @dev    Throws when calculated amounts are negative.
     *
     *         Calculates required token amounts based on current price relative to position range,
     *         updates tick information and bitmap, collects accrued fees, and modifies position state.
     *         Returns amounts for AMM to handle actual token transfers.
     *
     *         <h4>Postconditions</h4>
     *         1. The position ID, deposit amounts, and fees are returned to the caller.
     *         2. A DynamicPoolLiquidityAdded event is emitted with the pool ID, position ID, liquidity change and tick range.
     *
     * @param  poolId              Pool identifier for liquidity addition.
     * @param  ammBasePositionId   Base position identifier from AMM contract.
     * @param  poolParams          Encoded DynamicLiquidityModificationParams with tick range and liquidity amount.
     * @return positionId          Deterministic position identifier.
     * @return deposit0            Required amount of token0 for the liquidity addition.
     * @return deposit1            Required amount of token1 for the liquidity addition.
     * @return fees0               Accrued fees in token0 collected during operation.
     * @return fees1               Accrued fees in token1 collected during operation.
     */
    function addLiquidity(
        bytes32 poolId,
        address,
        bytes32 ammBasePositionId,
        bytes calldata poolParams
    ) external returns (
        bytes32 positionId,
        uint256 deposit0,
        uint256 deposit1,
        uint256 fees0,
        uint256 fees1
    ) {
        DynamicPoolStorage storage ammState = globalState[msg.sender];
        DynamicLiquidityModificationParams memory liquidityParams = abi.decode(poolParams, (DynamicLiquidityModificationParams));
        DynamicHelper.requireValidTicks(liquidityParams.tickLower, liquidityParams.tickUpper);

        if (liquidityParams.snapSqrtPriceX96 != 0) {
            DynamicHelper.snapPrice(ammState, poolId, liquidityParams.snapSqrtPriceX96);
        }

        positionId = EfficientHash.efficientHash(
            ammBasePositionId,
            bytes32(uint256(uint24(liquidityParams.tickLower))),
            bytes32(uint256(uint24(liquidityParams.tickUpper)))
        );

        DynamicPositionInfo storage position = ammState.poolPositions[positionId];

        ModifyDynamicLiquidityCache memory liquidityCache;
        liquidityCache.poolId = poolId;

        int128 liquidityChange = liquidityParams.liquidityChange;

        if (liquidityChange < 0) {
            revert DynamicPool__InvalidLiquidityChange();
        }

        DynamicHelper.modifyPosition(
            liquidityCache,
            ammState,
            position,
            liquidityParams.tickLower,
            liquidityParams.tickUpper,
            liquidityParams.liquidityChange
        );

        if (liquidityCache.amount0 < 0 || liquidityCache.amount1 < 0) {
            revert DynamicPool__InvalidAmountDeltas();
        }

        deposit0 = uint256(liquidityCache.amount0);
        deposit1 = uint256(liquidityCache.amount1);
        fees0 = liquidityCache.tokensOwed0;
        fees1 = liquidityCache.tokensOwed1;

        emit DynamicPoolLiquidityAdded(
            msg.sender,
            poolId,
            positionId,
            liquidityChange,
            liquidityParams.tickLower,
            liquidityParams.tickUpper
        );
    }

    /**
     * @notice Removes concentrated liquidity from a position within specified tick range.
     *
     * @dev    Throws when poolParams cannot be decoded as DynamicLiquidityModificationParams.
     * @dev    Throws when tickLower >= tickUpper.
     * @dev    Throws when tickUpper > MAX_TICK.
     * @dev    Throws when tickLower < MIN_TICK.
     * @dev    Throws when ticks are not aligned with tick spacing.
     * @dev    Throws when liquidityChange is positive.
     * @dev    Throws when calculated amounts are positive.
     *
     *         Calculates token amounts to withdraw based on current price relative to position range,
     *         updates tick information and bitmap, collects accrued fees, and modifies position state.
     *         Returns amounts for AMM to handle actual token transfers.
     *
     *         <h4>Postconditions</h4>
     *         1. The position ID, withdraw amounts, and fees are returned to the caller.
     *         2. A DynamicPoolLiquidityRemoved event is emitted with the pool ID, position ID, liquidity change and tick range.
     *
     * @param  poolId              Pool identifier for liquidity removal.
     * @param  ammBasePositionId   Base position identifier from AMM contract.
     * @param  poolParams          Encoded DynamicLiquidityModificationParams with tick range and negative liquidity amount.
     * @return positionId          Deterministic position identifier.
     * @return withdraw0           Amount of token0 to withdraw from the position.
     * @return withdraw1           Amount of token1 to withdraw from the position.
     * @return fees0               Accrued fees in token0 collected during operation.
     * @return fees1               Accrued fees in token1 collected during operation.
     */
    function removeLiquidity(
        bytes32 poolId,
        address,
        bytes32 ammBasePositionId,
        bytes calldata poolParams
    ) external returns (
        bytes32 positionId,
        uint256 withdraw0,
        uint256 withdraw1,
        uint256 fees0,
        uint256 fees1
    ) {
        DynamicPoolStorage storage ammState = globalState[msg.sender];
        DynamicLiquidityModificationParams memory liquidityParams = abi.decode(poolParams, (DynamicLiquidityModificationParams));
        DynamicHelper.requireValidTicks(liquidityParams.tickLower, liquidityParams.tickUpper);

        positionId = EfficientHash.efficientHash(
            ammBasePositionId,
            bytes32(uint256(uint24(liquidityParams.tickLower))),
            bytes32(uint256(uint24(liquidityParams.tickUpper)))
        );

        DynamicPositionInfo storage position = ammState.poolPositions[positionId];

        ModifyDynamicLiquidityCache memory liquidityCache;
        liquidityCache.poolId = poolId;

        int128 liquidityChange = liquidityParams.liquidityChange;

        if (liquidityChange > 0) {
            revert DynamicPool__InvalidLiquidityChange();
        }

        DynamicHelper.modifyPosition(
            liquidityCache,
            ammState,
            position,
            liquidityParams.tickLower,
            liquidityParams.tickUpper,
            liquidityParams.liquidityChange
        );


        if (liquidityCache.amount0 > 0 || liquidityCache.amount1 > 0) {
            revert DynamicPool__InvalidAmountDeltas();
        }

        withdraw0 = uint256(-liquidityCache.amount0);
        withdraw1 = uint256(-liquidityCache.amount1);
        fees0 = liquidityCache.tokensOwed0;
        fees1 = liquidityCache.tokensOwed1;

        emit DynamicPoolLiquidityRemoved(
            msg.sender,
            poolId,
            positionId,
            liquidityChange,
            liquidityParams.tickLower,
            liquidityParams.tickUpper
        );
    }

    /**
     * @notice Executes an input-based swap consuming up to the specified input for the calculated output.
     *
     * @dev    Throws when poolFeeBPS > MAX_BPS.
     *         Throws when protocolFeeBPS > MAX_BPS.
     *         Throws when DynamicHelper.computeSwap fails.
     *
     *         Performs concentrated liquidity swap by iterating through price ranges, crossing ticks
     *         as needed, and updating pool state. Uses DynamicHelper.computeSwap with an input-based step 
     *        function for amount calculations. Returns amounts for AMM to handle actual token transfers.
     *
     *         <h4>Postconditions</h4>
     *         1. The amount out, fees, and protocol fees are returned to the caller.
     *         2. A DynamicPoolSwapDetails event is emitted with the pool ID, current price, liquidity and tick.
     *
     * @param  poolId              Pool identifier for swap execution.
     * @param  zeroForOne          Swap direction: true for token0→token1, false for token1→token0.
     * @param  amountIn            Input amount to consume during swap.
     * @param  poolFeeBPS          Pool fee rate in basis points.
     * @param  protocolFeeBPS      Protocol fee rate in basis points.
     * @param  swapExtraData       Encoded parameters for price limit.
     * 
     * @return actualAmountIn      Input amount adjusted for partial fill.
     * @return amountOut           Output amount received from the swap.
     * @return feeOfAmountIn       Total fees charged on the input amount.
     * @return protocolFees        Protocol fees collected during the swap.
     */
    function swapByInput(
        SwapContext calldata,
        bytes32 poolId,
        bool zeroForOne,
        uint256 amountIn,
        uint256 poolFeeBPS,
        uint256 protocolFeeBPS,
        bytes calldata swapExtraData
    ) external returns (
        uint256 actualAmountIn,
        uint256 amountOut,
        uint256 feeOfAmountIn,
        uint256 protocolFees
    ) {
        if (poolFeeBPS > MAX_BPS || protocolFeeBPS > MAX_BPS) {
            revert DynamicPool__InvalidFeeBPS();
        }

        DynamicSwapCache memory swapCache = DynamicSwapCache({
            poolId: poolId,
            zeroForOne: zeroForOne,
            liquidity: 0,
            tick: 0,
            amountSpecified: amountIn,
            amountSpecifiedRemaining: amountIn,
            amountCalculated: 0,
            protocolFeeBPS: uint16(protocolFeeBPS),
            protocolFee: 0,
            feeAmount: 0,
            feeGrowthGlobalX128: 0,
            sqrtPriceLimitX96: 0,
            sqrtPriceCurrentX96: 0
        });

        {
            if (swapExtraData.length == 32) {
                swapCache.sqrtPriceLimitX96 = abi.decode(swapExtraData, (uint160));
            } else {
                if (swapCache.zeroForOne) {
                    swapCache.sqrtPriceLimitX96 = MIN_SQRT_RATIO + 1;
                } else {
                    swapCache.sqrtPriceLimitX96 = MAX_SQRT_RATIO - 1;
                }
            }
        }

        DynamicPoolStorage storage ammState = globalState[msg.sender];
        DynamicPoolState storage ptrPoolState = ammState.pools[poolId];
        DynamicPoolState memory poolState = ptrPoolState;
        
        swapCache.sqrtPriceCurrentX96 = poolState.sqrtPriceX96;
        swapCache.tick = poolState.tick;
        swapCache.liquidity = poolState.liquidity;

        if (swapCache.zeroForOne) {
            swapCache.feeGrowthGlobalX128 = poolState.feeGrowthGlobal0X128;
        } else {
            swapCache.feeGrowthGlobalX128 = poolState.feeGrowthGlobal1X128;
        }

        DynamicHelper.computeSwap(ammState, swapCache, poolState, uint16(poolFeeBPS), DynamicHelper._swapByInputStep);

        if (swapCache.tick != poolState.tick) {
            (ptrPoolState.sqrtPriceX96, ptrPoolState.tick) = (swapCache.sqrtPriceCurrentX96, swapCache.tick);
        } else {
            ptrPoolState.sqrtPriceX96 = swapCache.sqrtPriceCurrentX96;
        }

        if (poolState.liquidity != swapCache.liquidity) {
            ptrPoolState.liquidity = swapCache.liquidity;
        }

        if (swapCache.zeroForOne) {
            ptrPoolState.feeGrowthGlobal0X128 = swapCache.feeGrowthGlobalX128;
        } else {
            ptrPoolState.feeGrowthGlobal1X128 = swapCache.feeGrowthGlobalX128;
        }

        actualAmountIn = swapCache.amountSpecified - swapCache.amountSpecifiedRemaining;
        amountOut = swapCache.amountCalculated;
        feeOfAmountIn = swapCache.feeAmount;
        protocolFees = swapCache.protocolFee;

        emit DynamicPoolSwapDetails(
            msg.sender,
            poolId,
            swapCache.sqrtPriceCurrentX96,
            swapCache.liquidity,
            swapCache.tick
        );
    }

    /**
     * @notice Executes an output-based swap consuming the required input amount for the specified output.
     *
     * @dev    Throws when poolFeeBPS >= MAX_BPS.
     * @dev    Throws when protocolFeeBPS > MAX_BPS.
     * @dev    Throws when DynamicHelper.computeSwap fails.
     *
     *         Performs concentrated liquidity swap by iterating through price ranges, crossing ticks
     *         as needed, and updating pool state. Uses DynamicHelper.computeSwap with an output-based step
     *         function for amount calculations. Returns amounts for AMM to handle actual token transfers.
     *
     *         <h4>Postconditions</h4>
     *         1. The amount in, fees, and protocol fees are returned to the caller.
     *         2. A DynamicPoolSwapDetails event is emitted with the pool ID, current price, liquidity and tick.
     *
     * @param  poolId              Pool identifier for swap execution.
     * @param  zeroForOne          Swap direction: true for token0→token1, false for token1→token0.
     * @param  amountOut           Output amount to produce during swap.
     * @param  poolFeeBPS          Pool fee rate in basis points.
     * @param  protocolFeeBPS      Protocol fee rate in basis points.
     * @param  swapExtraData       Encoded parameters for price limit.
     * 
     * @return actualAmountOut     Output amount adjusted for partial fill.
     * @return amountIn            Input amount consumed during the swap.
     * @return feeOfAmountIn       Total fees charged on the input amount.
     * @return protocolFees        Protocol fees collected during the swap.
     */
    function swapByOutput(
        SwapContext calldata,
        bytes32 poolId,
        bool zeroForOne,
        uint256 amountOut,
        uint256 poolFeeBPS,
        uint256 protocolFeeBPS,
        bytes calldata swapExtraData
    ) external returns (
        uint256 actualAmountOut,
        uint256 amountIn,
        uint256 feeOfAmountIn,
        uint256 protocolFees
    ) {
        if (poolFeeBPS >= MAX_BPS || protocolFeeBPS > MAX_BPS) {
            revert DynamicPool__InvalidFeeBPS();
        }

        DynamicSwapCache memory swapCache = DynamicSwapCache({
            poolId: poolId,
            zeroForOne: zeroForOne,
            liquidity: 0,
            tick: 0,
            amountSpecified: amountOut,
            amountSpecifiedRemaining: amountOut,
            amountCalculated: 0,
            protocolFeeBPS: protocolFeeBPS,
            protocolFee: 0,
            feeAmount: 0,
            feeGrowthGlobalX128: 0,
            sqrtPriceLimitX96: 0,
            sqrtPriceCurrentX96: 0
        });

        {
            if (swapExtraData.length == 32) {
                swapCache.sqrtPriceLimitX96 = abi.decode(swapExtraData, (uint160));
            } else {
                if (swapCache.zeroForOne) {
                    swapCache.sqrtPriceLimitX96 = MIN_SQRT_RATIO + 1;
                } else {
                    swapCache.sqrtPriceLimitX96 = MAX_SQRT_RATIO - 1;
                }
            }
        }

        DynamicPoolStorage storage ammState = globalState[msg.sender];
        DynamicPoolState storage ptrPoolState = ammState.pools[poolId];
        DynamicPoolState memory poolState = ptrPoolState;

        swapCache.sqrtPriceCurrentX96 = poolState.sqrtPriceX96;
        swapCache.tick = poolState.tick;
        swapCache.liquidity = poolState.liquidity;

        if (swapCache.zeroForOne) {
            swapCache.feeGrowthGlobalX128 = poolState.feeGrowthGlobal0X128;
        } else {
            swapCache.feeGrowthGlobalX128 = poolState.feeGrowthGlobal1X128;
        }

        DynamicHelper.computeSwap(ammState, swapCache, poolState, uint16(poolFeeBPS), DynamicHelper._swapByOutputStep);

        if (swapCache.tick != poolState.tick) {
            (ptrPoolState.sqrtPriceX96, ptrPoolState.tick) = (swapCache.sqrtPriceCurrentX96, swapCache.tick);
        } else {
            ptrPoolState.sqrtPriceX96 = swapCache.sqrtPriceCurrentX96;
        }

        if (poolState.liquidity != swapCache.liquidity) {
            ptrPoolState.liquidity = swapCache.liquidity;
        }

        if (swapCache.zeroForOne) {
            ptrPoolState.feeGrowthGlobal0X128 = swapCache.feeGrowthGlobalX128;
        } else {
            ptrPoolState.feeGrowthGlobal1X128 = swapCache.feeGrowthGlobalX128;
        }

        actualAmountOut = swapCache.amountSpecified - swapCache.amountSpecifiedRemaining;
        amountIn = swapCache.amountCalculated;
        feeOfAmountIn = swapCache.feeAmount;
        protocolFees = swapCache.protocolFee;

        emit DynamicPoolSwapDetails(
            msg.sender,
            poolId,
            swapCache.sqrtPriceCurrentX96,
            swapCache.liquidity,
            swapCache.tick
        );
    }

    /**
     * @notice Returns the current square root price for a specific pool.
     *
     * @dev    View function that retrieves the current sqrtPriceX96 from pool state.
     *         Returns 0 if pool does not exist.
     *
     * @param  amm                 AMM contract address that owns the pool.
     * @param  poolId              Pool identifier to query.
     * @return sqrtPriceX96        Current square root price in Q64.96 fixed-point format.
     */
    function getCurrentPriceX96(
        address amm,
        bytes32 poolId
    ) external view returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = globalState[amm].pools[poolId].sqrtPriceX96;
    }

    /**
     * @notice Retrieves the current state of a specific pool for the provided AMM contract.
     *
     * @dev    View function that returns the current state of the pool including fee growth,
     *         current price, tick, and liquidity. Returns default values if pool does not exist
     *
     * @param  amm                 AMM contract address that owns the pool.
     * @param  poolId              Pool identifier to query.
     * @return poolState           Current state of the pool including fee growth, price, tick, and liquidity.
     */
    function getPoolState(
        address amm,
        bytes32 poolId
    ) external view returns (DynamicPoolState memory poolState) {
        poolState = globalState[amm].pools[poolId];
    }

    /**
     * @notice Retrieves position information for a specific AMM contract and position ID.
     *
     * @dev    View function that returns position information including tick range, liquidity, and fee growth.
     *         Returns default values if position does not exist.
     *
     * @param  amm                 AMM contract address that owns the position.
     * @param  positionId          Position identifier to query.
     * @return positionInfo        Information about the position including tick range, liquidity, and fee growth.
     */
    function getPositionInfo(
        address amm,
        bytes32 positionId
    ) external view returns (DynamicPositionInfo memory positionInfo) {
        positionInfo = globalState[amm].poolPositions[positionId];
    }

    /**
     * @notice Retrieves tick information for a specific AMM contract and tick index.
     *
     * @dev    View function that returns information about a specific tick including liquidity, fee growth, and initialization status.
     *         Returns default values if tick does not exist.
     *
     * @param  amm        AMM contract address that owns the pool.
     * @param  tick       Tick index to query.
     * @return tickInfo   Information about the tick including liquidity, fee growth, and initialization status.
     */
    function getTickInfo(
        address amm,
        bytes32 poolId,
        int24 tick
    ) external view returns (TickInfo memory tickInfo) {
        tickInfo = globalState[amm].poolTickInfo[EfficientHash.efficientHash(poolId, bytes32(uint256(int256(tick))))];
    }

    /**
     * @notice  Returns the manifest URI for the pool type to provide app integrations with
     *          information necessary to process transactions that utilize the pool type.
     * 
     * @dev     Hook developers **MUST** emit a `PoolTypeManifestUriUpdated` event if the URI
     *          changes.
     * 
     * @return  manifestUri  The URI for the hook manifest data. 
     */
    function poolTypeManifestUri() external pure returns(string memory manifestUri) {
        manifestUri = ""; //TODO: Before final deploy, create permalink for DynamicPoolType manifest
    }
}