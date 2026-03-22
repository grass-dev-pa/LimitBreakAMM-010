//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@limitbreak/lb-amm-core/src/interfaces/hooks/ILimitBreakAMMPoolHook.sol";

/**
 * @title  ISingleProviderPoolHook
 * @author Limit Break, Inc.
 * @notice Interface definition for a single provider pool's hook to get price and provider.
 */
interface ISingleProviderPoolHook is ILimitBreakAMMPoolHook {
    /**
     * @notice Parameters for fixed pool price calculation hooks
     * @dev    Used when hooks need to provide custom pricing for fixed pools
     * 
     * @param inputSwap  True for input-based swaps, false for output-based swaps.
     * @param poolId     Identifier of the pool.
     * @param tokenIn    Address of the input token.
     * @param tokenOut   Address of the output token.
     * @param amount     Amount being swapped.
     */
    struct HookPoolPriceParams {
        bool inputSwap;
        bytes32 poolId;
        address tokenIn;
        address tokenOut;
        uint256 amount;
    }

    /**
     * @notice  Executed during a swap operation on the single provider pool to return the price to execute the order at.
     * 
     * @param context          Context data for the swap from AMM core.
     * @param poolPriceParams  Swap parameters for the operation through the pool.
     * @param hookData         Arbitrary calldata provided with the operation for the pool hook.
     */
    function getPoolPriceForSwap(
        SwapContext calldata context,
        HookPoolPriceParams calldata poolPriceParams,
        bytes calldata hookData
    ) external returns (uint160 poolPrice);

    /**
     * @notice  Called during liquidity modification operations to determine if the caller is the owner of the liquidity in the pool.
     * 
     * @param  poolId    The identifier of the pool to return the liquidity provider for.
     * @return provider  Address of the liquidity provider for the pool.
     */
    function getPoolLiquidityProvider(
        bytes32 poolId
    ) external view returns (address provider);
}