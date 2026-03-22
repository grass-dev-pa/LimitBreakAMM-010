//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/**
 * @dev Parameters for creating a single-provider pool.
 * 
 * @dev **salt**:              Unique salt used to ensure deterministic pool deployment address.
 * @dev **sqrtPriceRatioX96**: Initial price ratio as sqrt(price) * 2^96
 */
struct SingleProviderPoolCreationDetails {
    bytes32 salt;
    uint160 sqrtPriceRatioX96;
}

/**
 * @dev State data for a single-provider pool.
 * 
 * @dev **lastSqrtPriceX96**: Last recorded sqrt price (Q64.96 fixed-point) for the pool.
 */
struct SingleProviderPoolState {
    uint160 lastSqrtPriceX96;
}

/**
 * @notice Parameters for modifying single-provider pool liquidity.
 * @dev    Used when adding or removing liquidity from single-provider pools.
 * 
 * @dev **amount0**: Maximum amount of token0 to add or exact amount to remove.
 * @dev **amount1**: Maximum amount of token1 to add or exact amount to remove.
 */
struct SingleProviderLiquidityModificationParams {
    uint256 amount0;
    uint256 amount1;
}

/**
 * @dev Temporary storage for swap execution state in single-provider pools.
 * 
 * @dev **poolHook**: Address of the pool price hook.
 * @dev **zeroForOne**: True if swapping token0 for token1, false for token1 for token0.
 * @dev **amountIn**: Input amount for the swap operation.
 * @dev **amountOut**: Output amount calculated for the swap.
 * @dev **protocolFeeBPS**: Protocol fee rate in basis points.
 * @dev **protocolFee**: Protocol fee amount collected from this swap.
 * @dev **feeAmount**: Total fee amount (protocol + LP fees) for this swap.
 * @dev **sqrtPriceCurrentX96** Current sqrt price ratio during execution.
 * @dev **reserveOut**: Current available reserve of the output token.
 */
struct SingleProviderSwapCache {
    address poolHook;
    bool zeroForOne;
    uint256 amountIn;
    uint256 amountOut;
    uint16 protocolFeeBPS;
    uint256 protocolFee;
    uint256 feeAmount;
    uint160 sqrtPriceCurrentX96;
    uint256 reserveOut;
}