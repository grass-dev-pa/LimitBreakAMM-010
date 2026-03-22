//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMSwap
 * @author Limit Break, Inc.
 * @notice Interface definition for AMM core swap execution functions.
 */
interface ILimitBreakAMMSwap {
    /**
     * @notice Executes a token swap in a single pool, delegating all pool logic to the external module registered for the pool type.
     *
     * @dev    Throws when the swap deadline has expired.
     *         Throws when the recipient address is zero.
     *         Throws when the exchange fee or fee-on-top configuration is invalid.
     *         Throws when the specified pool does not exist.
     *         Throws when there is insufficient liquidity for the trade.
     *         Throws when the limit amount requirements are not met.
     *         Throws when any hook validation fails.
     *
     *         This function is invariant-agnostic and does not implement pool logic directly. All swap mechanics,
     *         including price movement, liquidity checks, and invariant enforcement, are delegated to the external
     *         module associated with the given poolId. The protocol supports arbitrary pool types and invariants
     *         through this modular architecture.
     *
     *         Comprehensive hook validations are performed before and after the swap, including token, pool, and
     *         transfer handler hooks. Fee structures are applied according to protocol and pool configuration.
     *         Native token operations and custom transfer handlers are supported for advanced payment flows.
     *
     *         <h4>Postconditions:</h4>
     *         1. The pool state is updated according to the swap logic defined by the external module.
     *         2. Input tokens (including all applicable fees) are collected from the executor.
     *         3. Output tokens are transferred to the recipient.
     *         4. Exchange fees and fees-on-top are transferred to their designated recipients.
     *         5. Protocol fees are stored for later collection.
     *         6. All applicable swap hooks are executed successfully.
     *         7. A swap event is emitted with operation details.
     *
     * @param swapOrder           Struct containing swap parameters:
     *                              - deadline: Timestamp by which the swap must be executed.
     *                              - recipient: Address to receive the output tokens.
     *                              - amountSpecified: Amount of token0 or token1 to swap.
     *                              - limitAmount: Minimum output (for input-based) or maximum input (for output-based).
     *                              - tokenIn: Address of the input token.
     *                              - tokenOut: Address of the output token.
     * @param poolId              Unique identifier for the pool to execute the swap in.
     * @param exchangeFee         Struct specifying the exchange fee configuration and recipient.
     * @param feeOnTop            Struct specifying any additional flat fee and recipient.
     * @param swapHooksExtraData  Struct containing hook-specific data for token and pool validations.
     * @param transferData        Optional data for custom transfer handlers (advanced payment flows).
     * @return amountIn           Total input tokens collected (including fees).
     * @return amountOut          Output tokens transferred to the recipient.
     */
    function singleSwap(
        SwapOrder calldata swapOrder,
        bytes32 poolId,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        SwapHooksExtraData calldata swapHooksExtraData,
        bytes calldata transferData
    ) external payable returns (uint256 amountIn, uint256 amountOut);

    /**
     * @notice Executes a multi-hop token swap across multiple pools, delegating all pool logic to the external modules registered for each pool type.
     *
     * @dev    Throws when the swap deadline has expired.
     *         Throws when the recipient address is zero.
     *         Throws when the exchange fee or fee-on-top configuration is invalid.
     *         Throws when the poolIds and swapHooksExtraDatas arrays have mismatched lengths.
     *         Throws when any pool in the route does not exist.
     *         Throws when there is insufficient liquidity for any trade in the route.
     *         Throws when the limit amount requirements are not met.
     *         Throws when any hook validation fails.
     *
     *         This function is invariant-agnostic and does not implement pool logic directly. For each hop,
     *         all swap mechanics—including price movement, liquidity checks, and invariant enforcement—are delegated
     *         to the external module associated with the given poolId. The protocol supports arbitrary pool types
     *         and invariants through this modular architecture, enabling complex multi-hop routes.
     *
     *         Each intermediate swap output becomes the input for the next hop. Comprehensive hook validations are
     *         performed for every hop, including token, pool, and transfer handler hooks. Fee structures are applied
     *         according to protocol and pool configuration. Native token operations and custom transfer handlers are
     *         supported for advanced payment flows.
     *
     *         Protocol fees are accumulated and stored during intermediate swaps, while exchange fees and fees-on-top
     *         are applied only to the final amounts. All hooks are executed for each swap step to ensure comprehensive
     *         validation throughout the route.
     *
     *         <h4>Postconditions:</h4>
     *         1. All pools in the route are updated according to their respective swap logic as defined by their external modules.
     *         2. Input tokens (including all applicable fees) are collected from the executor.
     *         3. Output tokens are transferred to the recipient.
     *         4. Exchange fees and fees-on-top are transferred to their designated recipients.
     *         5. Protocol fees are stored for each intermediate swap.
     *         6. All applicable swap hooks are executed for each pool in the route.
     *         7. A final swap event is emitted with complete route details.
     *
     * @param swapOrder            Struct containing swap parameters:
     *                               - deadline: Timestamp by which the swap must be executed.
     *                               - recipient: Address to receive the output tokens.
     *                               - amountSpecified: Amount of token0 or token1 to swap.
     *                               - limitAmount: Minimum output (for input-based) or maximum input (for output-based).
     *                               - tokenIn: Address of the input token.
     *                               - tokenOut: Address of the output token.
     * @param poolIds              Array of unique identifiers for the pools to swap tokens in.
     * @param exchangeFee          Struct specifying the exchange fee configuration and recipient.
     * @param feeOnTop             Struct specifying any additional flat fee and recipient.
     * @param swapHooksExtraDatas  Array of structs containing hook-specific data for token and pool validations for each hop.
     * @param transferData         Optional data for custom transfer handlers (advanced payment flows).
     * @return amountIn            Total input tokens collected (including fees).
     * @return amountOut           Output tokens transferred to the recipient.
     */
    function multiSwap(
        SwapOrder calldata swapOrder,
        bytes32[] calldata poolIds,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        SwapHooksExtraData[] calldata swapHooksExtraDatas,
        bytes calldata transferData
    ) external payable returns (uint256 amountIn, uint256 amountOut);

    /**
     * @notice Executes a direct token swap at a fixed exchange rate without using AMM pool liquidity.
     *
     * @dev    Throws when deadline has expired.
     *         Throws when recipient is zero address.
     *         Throws when fee configuration is invalid.
     *         Throws when pool hook data is provided.
     *         Throws when token transfers fail.
     *         Throws when hook validations fail.
     *
     *         Performs peer-to-peer token exchange using the limit amount specified in the swap order
     *         as the fixed exchange rate. Unlike pool-based swaps, direct swaps do not utilize AMM
     *         liquidity or affect pool states. The executor provides the output tokens directly in
     *         exchange for receiving the input tokens at the predetermined rate.
     *
     *         Executes token-level hooks for validation and fee collection, applies exchange fees and
     *         fees-on-top, handles wrapped native token operations, and supports custom transfer
     *         handlers for complex payment flows. Pool hooks are not supported for direct swaps. Exchange fees and
     *         fees-on-top are calculated independently and applied in addition to any hook fees.
     *
     *         <h4>Postconditions:</h4>
     *         1. Input tokens collected from executor at specified amounts
     *         2. Output tokens transferred from executor to recipient
     *         3. Exchange fees transferred to designated recipient
     *         4. Fee-on-top transferred to designated recipient
     *         5. Token hooks executed for validation and fee collection
     *         6. DirectSwap event emitted with operation details
     *
     * @param  swapOrder          Order parameters including tokens, amounts, and recipient.
     * @param  exchangeFee        Exchange fee configuration and recipient address.
     * @param  feeOnTop           Additional flat fee configuration and recipient address.
     * @param  swapHooksExtraData Hook-specific data for token validation (pool hooks not supported).
     * @param  transferData       Optional custom transfer handler data for complex payment flows.
     * @return amountIn           Total amount of input tokens collected including fees.
     * @return amountOut          Amount of output tokens transferred to recipient.
     */
    function directSwap(
        SwapOrder calldata swapOrder,
        DirectSwapParams calldata directSwapParams,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        SwapHooksExtraData calldata swapHooksExtraData,
        bytes calldata transferData
    ) external payable returns (uint256 amountIn, uint256 amountOut);
}
