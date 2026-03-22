//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

// =============================================================================
//                              CORE TYPES
// =============================================================================

/**
 * @dev Main storage structure for the AMM containing all state variables.
 * @dev Primary storage struct for the AMM system, containing mappings for all pool and position data.
 *
 * @dev **protocolFeeStructure**         Global protocol fee configuration.
 * @dev **tokenSettings**                Mapping of token addresses to their individual settings and hooks.
 * @dev **pools**                        Mapping of pool IDs to pool state.
 * @dev **protocolFees**                 Mapping of token addresses to accumulated protocol fees.
 * @dev **flashLoanBPS**                 Flash loan fee in basis points.
 * @dev **tokensOwed**                   Complex mapping for tracking owed tokens across different scenarios:
 *                                          - For hook-managed fees: keccak256(tokenHook, keccak256(tokenFor, tokenFee))
 *                                          - For direct fees: keccak256(tokenFor, tokenFee)
 *                                          - For position fees: keccak256(owedTo, tokenOwed)
 * @dev **poolInitialized**              Mapping to track if a pool has been initialized.
 * @dev **lpProtocolFeeOverride**        Mapping of poolId to protocol fee overrides.
 * @dev **exchangeProtocolFeeOverride**  Mapping of exchange fee recipient addresses to protocol fee overrides.
 * @dev **feeOnTopProtocolFeeOverride**  Mapping of fee on top recipient addresses to protocol fee overrides.
 */
struct LBAMMStorage {
    ProtocolFeeStructure protocolFeeStructure;
    mapping(address => TokenSettings) tokenSettings;
    mapping(bytes32 => PoolState) pools;
    mapping(address => uint256) protocolFees;
    uint16 flashLoanBPS;
    mapping(bytes32 => uint256) tokensOwed;
    mapping(bytes32 => bool) poolInitialized;
    mapping(bytes32 => ProtocolFeeOverride) lpProtocolFeeOverride;
    mapping(address => ProtocolFeeOverride) exchangeProtocolFeeOverride;
    mapping(address => ProtocolFeeOverride) feeOnTopProtocolFeeOverride;
}

/**
 * @dev State data for a pool.
 *
 * @dev **token0**        Address of the first token in the pool.
 * @dev **token1**        Address of the second token in the pool.
 * @dev **poolHook**      Address of the pool-specific hook contract.
 * @dev **reserve0**      Current reserve of token0.
 * @dev **reserve1**      Current reserve of token1.
 * @dev **feeBalance0**   Unclaimed fees accrued for token0.
 * @dev **feeBalance1**   Unclaimed fees accrued for token1.
 */
struct PoolState {
    address token0;
    address token1;
    address poolHook;
    uint128 reserve0;
    uint128 reserve1;
    uint128 feeBalance0;
    uint128 feeBalance1;
}

/**
 * @dev Protocol fee structure defining how fees are collected across the system.
 *
 * @dev **lpFeeBPS**          Fee in basis points assessed on LP fees collected.
 * @dev **exchangeFeeBPS**    Fee in basis points assessed on exchange fees.
 * @dev **feeOnTopBPS**       Fee in basis points assessed on additional fees.
 */
struct ProtocolFeeStructure {
    uint16 lpFeeBPS;
    uint16 exchangeFeeBPS;
    uint16 feeOnTopBPS;
}

/**
 * @dev Protocol fee override struct for allowing different protocol fee rates by address.
 *
 * @dev **feeOverrideEnabled**  True if the fee override is enabled.
 * @dev **protocolFeeBPS**      Protocol fee rate to apply in BPS.
 */
struct ProtocolFeeOverride {
    bool feeOverrideEnabled;
    uint16 protocolFeeBPS;
}

/**
 * @dev Token-level settings and configurations.
 * @dev Contains token-specific settings including fees, packed configuration flags, and hook address.
 *
 * @dev **hopFeeBPS**       Fee in basis points for multi-hop swaps involving this token.
 * @dev **packedSettings**  Bit-packed configuration flags:
 *                            - Bits 0-9: Hook flags
 *                            - Bit 10: Require executor pays
 * @dev **tokenHook**       Address of the hook contract for this token (zero address = no hook).
 */
struct TokenSettings {
    uint16 hopFeeBPS;
    uint32 packedSettings;
    address tokenHook;
}

/**
 * @dev Parameters for creating a new pool.
 * @dev Used by the AMM to deploy new pools of any type.
 *
 * @dev **poolType**    Address of the pool type contract.
 * @dev **fee**         Pool fee in basis points (max 10000 = 100%).
 * @dev **token0**      Address of the first token (must be < token1 for consistent ordering).
 * @dev **token1**      Address of the second token (must be > token0 for consistent ordering).
 * @dev **poolHook**    Address of the pool-specific hook contract (zero address = no hook).
 * @dev **poolParams**  Encoded parameters for the pool type initialization. Must match the pool type's abi to be decoded correctly.
 */
struct PoolCreationDetails {
    address poolType;
    uint16 fee;
    address token0;
    address token1;
    address poolHook;
    bytes poolParams;
}

/**
 * @dev Fixed fee configuration with recipient.
 * @dev Defines a flat fee amount and who receives it.
 *
 * @dev **recipient** Address that will receive the fee.
 * @dev **amount**    Fixed fee amount in wei.
 */
struct FlatFeeWithRecipient {
    address recipient;
    uint256 amount;
}

/**
 * @dev Basis points fee configuration with recipient.
 * @dev Defines a percentage-based fee and who receives it.
 *
 * @dev **recipient** Address that will receive the fee.
 * @dev **BPS**       Fee in basis points (1 BPS = 0.01%, max value depends on uint size).
 */
struct BPSFeeWithRecipient {
    address recipient;
    uint256 BPS;
}

/**
 * @dev Internal cache for swap execution.
 * @dev Used during swap execution to cache intermediate values and avoid stack overflow issues.
 *      Contains context, fee calculations, pool state, and temporary computation values.
 *
 * @dev **context**                    Swap context information.
 * @dev **inputSwap**                  True if this is an input-based swap, false if output-based swap.
 * @dev **protocolFeeStructure**       Protocol fee configuration.
 * @dev **defaultProtocolLPFeeBPS**    Default protocol LP fee BPS if not overridden.
 * @dev **adjustedAmountSpecified**    Adjusted amount specified for handling partial fill of first swap.
 * @dev **minAmountSpecified**         Minimum amount of the specified token allowed for the swap in the event of a partial fill.
 * @dev **feeOnTopAmount**             Additional fee amount.
 * @dev **exchangeFeeAmount**          Exchange fee amount.
 * @dev **protocolExchangeFeeAmount**  Protocol share of exchange fee, stored on input-based swaps for adjusting partial fills.
 * @dev **protocolFeeFromFees**        Protocol fee derived from other fees.
 * @dev **hookLongestData**            Length of the longest hook data (for memory allocation).
 * @dev **hookMemoryPointer**          Memory pointer for hook data storage.
 * @dev **callbackMemoryPointer**      Memory pointer for transfer handler callback data storage.
 * @dev **msgValueUsed**               True when msg value was used as part of a direct swap flow.
 * @dev **hopIndex**                   Zero-based index of the swap. Will always be zero for single hop swaps.
 * @dev **poolId**                     Current pool identifier.
 * @dev **zeroForOne**                 Direction of swap (token0 to token1 or vice versa).
 * @dev **tokenIn**                    Current input token address.
 * @dev **tokenOut**                   Current output token address.
 * @dev **nextToken**                  Next token in multi-hop swap.
 * @dev **amountIn**                   Total input amount for the swap.
 * @dev **amountOut**                  Total output amount for the swap.
 * @dev **expectedLPFee**              Expected pool fee on input swaps.
 * @dev **expectedProtocolLPFee**      Expected protocol fee of pool fee.
 * @dev **protocolFee**                Protocol fee for this swap.
 * @dev **tokenInTokenInFee**          Fee on input token charged by input token hook.
 * @dev **tokenOutTokenInFee**         Fee on input token charged by output token hook.
 * @dev **tokenInTokenOutFee**         Fee on output token charged by input token hook.
 * @dev **tokenOutTokenOutFee**        Fee on output token charged by output token hook.
 */
struct InternalSwapCache {
    // Top Level Params
    SwapContext context;
    bool inputSwap;
    ProtocolFeeStructure protocolFeeStructure;
    uint16 defaultProtocolLPFeeBPS;
    uint256 adjustedAmountSpecified;
    uint256 minAmountSpecified;
    uint256 feeOnTopAmount;
    uint256 exchangeFeeAmount;
    uint256 protocolExchangeFeeAmount;
    uint256 protocolFeeFromFees;
    uint256 hookLongestData;
    uint256 hookMemoryPointer;
    uint256 callbackMemoryPointer;
    bool msgValueUsed;
    // Swap Level Params
    uint256 hopIndex;
    bytes32 poolId;
    bool zeroForOne;
    address tokenIn;
    address tokenOut;
    address nextToken;
    uint256 amountIn;
    uint256 amountOut;
    uint256 expectedLPFee;
    uint256 expectedProtocolLPFee;
    uint256 protocolFee;
    uint256 tokenInTokenInFee;
    uint256 tokenOutTokenInFee;
    uint256 tokenInTokenOutFee;
    uint256 tokenOutTokenOutFee;
}

/**
 * @dev Internal cache for liquidity modification execution.
 * @dev Used during liquidity modification execution to cache intermediate values and avoid
 *      stack overflow issues.
 * 
 * @dev **amount0**  Amount to deposit or withdraw of token0.
 * @dev **amount1**  Amount to deposit or withdraw of token1.
 * @dev **fees0**    Amount of fees for the position in token0.
 * @dev **fees1**    Amount of fees for the position in token1.
 */
struct InternalLiquidityModificationCache {
    uint256 amount0;
    uint256 amount1;
    uint256 fees0;
    uint256 fees1;
}

// =============================================================================
//                              HOOK TYPES
// =============================================================================

/**
 * @dev Hook data for swap operations.
 * @dev Contains calldata for different hooks that can be triggered during swaps.
 *
 * @dev **tokenInHook**  Calldata for the input token's hook contract.
 * @dev **tokenOutHook** Calldata for the output token's hook contract.
 * @dev **poolHook**     Calldata for the pool's hook contract.
 * @dev **poolType**     Calldata for the pool type contract.
 */
struct SwapHooksExtraData {
    bytes tokenInHook;
    bytes tokenOutHook;
    bytes poolHook;
    bytes poolType;
}

/**
 * @dev Context information passed to swap hooks.
 * @dev Provides hooks with information about the current swap operation.
 *
 * @dev **executor**             Address responsible for executing the swap (may differ from caller).
 * @dev **transferHandler**      Address of the optional transfer handler for settling a swap.
 * @dev **exchangeFeeRecipient** Address that will receive the exchange fee.
 * @dev **exchangeFeeBPS**       Exchange fee rate in BPS that will apply to the input token.
 * @dev **feeOnTopRecipient**    Address that will receive the fee on top.
 * @dev **feeOnTopAmount**       Fee on top amount that will be taken from swap token in.
 * @dev **recipient**            Address that will receive the output tokens.
 * @dev **tokenIn**              Address of the input token.
 * @dev **tokenOut**             Address of the output token.
 * @dev **numberOfHops**         Number of hops in the swap.
 */
struct SwapContext {
    address executor;
    address transferHandler;
    address exchangeFeeRecipient;
    uint256 exchangeFeeBPS;
    address feeOnTopRecipient;
    uint256 feeOnTopAmount;
    address recipient;
    address tokenIn;
    address tokenOut;
    uint256 numberOfHops;
}

/**
 * @dev Hook data for liquidity operations.
 * @dev Contains calldata for different hooks that can be triggered during liquidity modifications.
 *
 * @dev **token0Hook**    Calldata for token0's hook contract.
 * @dev **token1Hook**    Calldata for token1's hook contract.
 * @dev **liquidityHook** Calldata for the position's liquidity hook contract.
 * @dev **poolHook**      Calldata for the pool's hook contract.
 */
struct LiquidityHooksExtraData {
    bytes token0Hook;
    bytes token1Hook;
    bytes liquidityHook;
    bytes poolHook;
}

/**
 * @dev Parameters for modifying pool liquidity.
 * @dev Used when adding or removing liquidity from pools.
 *
 * @dev **liquidityHook**        Address of the liquidity hook for this position.
 * @dev **poolId**               Identifier of the target pool.
 * @dev **minLiquidityAmount0**  Minimum amount of token0 to receive on withdrawal (provide on deposit). This amount is exclusive of hook fees which will decrease withdrawal amounts (increase deposit amounts).
 * @dev **minLiquidityAmount1**  Minimum amount of token1 to receive on withdrawal (provide on deposit). This amount is exclusive of hook fees which will decrease withdrawal amounts (increase deposit amounts).
 * @dev **maxLiquidityAmount0**  Maximum amount of token0 to receive on withdrawal (provide on deposit). This amount is exclusive of hook fees which will decrease withdrawal amounts (increase deposit amounts).
 * @dev **maxLiquidityAmount1**  Maximum amount of token1 to receive on withdrawal (provide on deposit). This amount is exclusive of hook fees which will decrease withdrawal amounts (increase deposit amounts).
 * @dev **maxHookFee0**          Maximum hook fee of token0 to allow.
 * @dev **maxHookFee1**          Maximum hook fee of token1 to allow.
 * @dev **poolParams**           Encoded parameters for the pool type.
 */
struct LiquidityModificationParams {
    address liquidityHook;
    bytes32 poolId;
    uint256 minLiquidityAmount0;
    uint256 minLiquidityAmount1;
    uint256 maxLiquidityAmount0;
    uint256 maxLiquidityAmount1;
    uint256 maxHookFee0;
    uint256 maxHookFee1;
    bytes poolParams;
}

/**
 * @dev Parameters for collecting pool fees.
 * @dev Used when collecting fees from pools.
 *
 * @dev **liquidityHook**    Address of the liquidity hook for this position.
 * @dev **poolId**           Identifier of the target pool.
 * @dev **maxHookFee0**      Maximum hook fee of token0 to allow.
 * @dev **maxHookFee1**      Maximum hook fee of token1 to allow.
 * @dev **poolParams**       Encoded parameters for the pool type.
 */
struct LiquidityCollectFeesParams {
    address liquidityHook;
    bytes32 poolId;
    uint256 maxHookFee0;
    uint256 maxHookFee1;
    bytes poolParams;
}

/**
 * @dev Context information passed to liquidity hooks.
 * @dev Provides hooks with information about the current liquidity operation.
 *
 * @dev **provider**   Address providing or removing liquidity.
 * @dev **token0**     Address of token0 in the pool.
 * @dev **token1**     Address of token1 in the pool.
 * @dev **positionId** Unique identifier for the liquidity position within the pool type.
 */
struct LiquidityContext {
    address provider;
    address token0;
    address token1;
    bytes32 positionId;
}

/**
 * @dev Parameters for swap hook functions.
 * @dev Provides standardized parameters for before/after swap hook calls.
 *
 * @dev **inputSwap**         True for input swaps, false for output swaps.
 * @dev **hopIndex**          Zero-based index of the swap. Will always be zero for single hop swaps.
 * @dev **poolId**            Identifier of the pool being swapped in.
 * @dev **tokenIn**           Address of the input token.
 * @dev **tokenOut**          Address of the output token.
 * @dev **amount**            Amount being swapped (interpretation depends on inputSwap).
 * @dev **hookForInputToken** True if this hook call is for the input token, false for output token.
 */
struct HookSwapParams {
    bool inputSwap;
    uint256 hopIndex;
    bytes32 poolId;
    address tokenIn;
    address tokenOut;
    uint256 amount;
    bool hookForInputToken;
}

/**
 * @dev Parameters for pool fee calculation hooks.
 * @dev Used when hooks need to calculate custom pool fees.
 *
 * @dev **inputSwap**  True for input swaps, false for output swaps.
 * @dev **hopIndex**   Zero-based index of the swap. Will always be zero for single hop swaps.
 * @dev **poolId**     Identifier of the pool.
 * @dev **tokenIn**    Address of the input token.
 * @dev **tokenOut**   Address of the output token.
 * @dev **amount**     Amount being swapped.
 */
struct HookPoolFeeParams {
    bool inputSwap;
    uint256 hopIndex;
    bytes32 poolId;
    address tokenIn;
    address tokenOut;
    uint256 amount;
}

// =============================================================================
//                              FLASHLOAN TYPES
// =============================================================================

/**
 * @dev Parameters for requesting a flashloan.
 * @dev Contains all information needed to execute a flashloan.
 *
 * @dev **loanToken**      Address of the token to borrow.
 * @dev **loanAmount**     Amount of tokens to borrow.
 * @dev **executor**       Address that will receive the borrowed tokens and execute the callback.
 * @dev **executorData**   Arbitrary data passed to the executor's callback function.
 * @dev **tokenHookData**  Data passed to the borrowed token's hook (if any).
 * @dev **feeTokenHookData** Data passed to the fee token's hook (if different from loan token).
 */
struct FlashloanRequest {
    address loanToken;
    uint256 loanAmount;
    address executor;
    bytes executorData;
    bytes tokenHookData;
    bytes feeTokenHookData;
}

// =============================================================================
//                                SWAP TYPES
// =============================================================================

/**
 * @dev Parameters defining a swap order.
 * @dev Contains all information needed to execute a token swap.
 *
 * @dev **deadline**            Unix timestamp after which the swap will revert.
 * @dev **recipient**           Address that will receive the output tokens.
 * @dev **amountSpecified**     Amount of specified token (positive for input-based swaps, negative for output-based swaps).
 * @dev **minAmountSpecified**  Minimum amount of the specified token allowed for the swap in the event of a partial fill.
 * @dev **limitAmount**         Maximum input (for output swaps) or minimum output (for input swaps).
 * @dev **tokenIn**             Address of the input token.
 * @dev **tokenOut**            Address of the output token.
 */
struct SwapOrder {
    uint256 deadline;
    address recipient;
    int256 amountSpecified;
    uint256 minAmountSpecified;
    uint256 limitAmount;
    address tokenIn;
    address tokenOut;
}

/**
 * @dev Parameters for direct token swaps.
 * @dev Used to execute direct swaps with limits on amount in and amount out.
 * @dev On direct swaps, the executor supplies output token to fill an order through a transfer handler while
 *      receiving the input token from the order.
 *
 * @dev **swapAmount**    Exact amount of token to swap.
 * @dev **maxAmountOut**  Maximum amount of output token to be supplied by the executor.
 * @dev **minAmountIn**   Minimum amount of input tokens to be received by the executor.
 */
struct DirectSwapParams {
    uint256 swapAmount;
    uint256 maxAmountOut;
    uint256 minAmountIn;
}
