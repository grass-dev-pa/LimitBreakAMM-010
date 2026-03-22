//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./modules/AMMModule.sol";
import "./interfaces/ILimitBreakAMM.sol";

import "@limitbreak/tm-core-lib/src/utils/misc/DelegateCall.sol";
import "@limitbreak/tm-core-lib/src/utils/misc/StaticDelegateCall.sol";

import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  LimitBreakAMM
 * @author Limit Break, Inc.
 *
 * @notice Core entry point for all swap, liquidity, and protocol operations in the Limit Break AMM system.
 *
 * @dev    This contract implements a modular, extensible AMM architecture supporting many pool types. All user and 
 *         admin operations are routed through this contract, which delegates core logic to external module contracts 
 *         and enforces protocol-level permissions.
 *
 *         The LimitBreakAMM is designed to be a generic AMM framework that can support a wide range of pool types and behaviors.
 *         Pool types are not hardcoded into this contract; instead, they are defined by external modules that implement specific
 *         invariants and behaviors.
 *
 *         Key architectural components:
 *         - ModuleAdmin: Manages protocol fees, token settings, and administrative operations.
 *         - ModuleLiquidity: Provides pool creation, liquidity management and flash loan functionality.
 *         - ModuleFeeCollection: Handles protocol and hook fee collection.
 *         - Hook system: Token, position, and pool-level validation and fee collection.
 *         - External pool types: Pool types are separate and designed to be independent invariant implementations.
 */
contract LimitBreakAMM is AMMModule, ILimitBreakAMM, DelegateCall, StaticDelegateCall {
    /// @dev the address of the advanced execution module.
    address private immutable MODULE_LIQUIDITY;

    /// @dev the address of the advanced execution module.
    address private immutable MODULE_ADMIN;

    /// @dev the address of the advanced execution module.
    address private immutable MODULE_FEE_COLLECTION;

    constructor(
        address wrappedNative_,
        address moduleLiquidity_,
        address moduleAdmin_,
        address moduleFeeCollection_
    ) AMMModule(wrappedNative_) {
        MODULE_LIQUIDITY = moduleLiquidity_;
        MODULE_ADMIN = moduleAdmin_;
        MODULE_FEE_COLLECTION = moduleFeeCollection_;
    }

    ///////////////////////////////////////////////////////
    //                   POOL CREATION                   //
    ///////////////////////////////////////////////////////

    /**
     * @notice Creates a new pool with the specified parameters and initial price.
     *
     * @dev    Throws when a pool with the same parameters already exists.
     *         Throws when pool details are invalid or unsupported by the selected pool type.
     *         Throws when any token in the pool has restrictions that are violated.
     *         Throws when the initial sqrt price is outside valid bounds for the pool type.
     *         Throws when any hook validation fails.
     *         Throws when liquidity data is provided with a function selector that does not match the `addLiquidity` function.
     *         Throws when liquidity data is provided and the `addLiquidity` function reverts.
     *         Throws when native token value is provided but not used for adding liquidity.
     *
     *         Pool IDs are generated deterministically from the pool parameters, ensuring uniqueness
     *         regardless of creation order. Token and pool restrictions are enforced through hook
     *         validations at creation time. The pool is initialized with the specified sqrt price and
     *         default state for its type as defined by the pool type module.
     *
     *         Pool type modules and hooks may throw custom errors if validation fails.
     *
     *         <h4>Postconditions:</h4>
     *         1. Pool ID generated and stored in the appropriate pool mapping.
     *         2. Pool initialized with specified sqrt price and default state.
     *         3. Token and pool hooks executed for validation.
     *         4. PoolCreated event emitted for the new pool.
     *         5. Optionally, `addLiquidity` function is called to add liquidity to the pool.
     *
     * @param  details         Pool creation parameters (see PoolCreationDetails).
     * @param  token0HookData  Hook data for the first token's validation.
     * @param  token1HookData  Hook data for the second token's validation.
     * @param  poolHookData    Hook data for pool-level validation.
     * @param  liquidityData   Calldata to make call to `addLiquidity` function after pool creation.
     * @return poolId          The deterministic hash identifier of the created pool.
     * @return deposit0        Amount of token0 deposited into the pool.
     * @return deposit1        Amount of token1 deposited into the pool.
     */
    function createPool(
        PoolCreationDetails memory details,
        bytes calldata token0HookData,
        bytes calldata token1HookData,
        bytes calldata poolHookData,
        bytes calldata liquidityData
    ) external payable delegateCallPure(MODULE_LIQUIDITY) returns (bytes32 poolId, uint256 deposit0, uint256 deposit1) { }

    ///////////////////////////////////////////////////////
    //                 TOKEN MANAGEMENT                  //
    ///////////////////////////////////////////////////////

    /**
     * @notice Configures token settings including hook integration and operational flags.
     *
     * @dev    Throws when caller is not token owner, contract owner, or admin.
     *         Throws when hook flags are missing required flags.
     *         Throws when hook flags include unsupported flags.
     *
     *         Updates token configuration with hook contract address and packed settings flags.
     *         Validates hook flag compatibility against hook contract requirements and capabilities.
     *         Only authorized parties can modify token settings for security.
     *
     *         <h4>Postconditions:</h4>
     *         1. Token settings updated in storage with new hook and flags
     *         2. Hook flag validation completed against required and supported flags
     *         3. TokenSettingsUpdated event emitted with configuration details
     *
     * @param  token          Token address to configure settings for.
     * @param  tokenHook      Hook contract address for token operations.
     * @param  packedSettings Bit-packed configuration flags for token behavior.
     */
    function setTokenSettings(address token, address tokenHook, uint32 packedSettings)
        external delegateCallPure(MODULE_ADMIN) { }

    ///////////////////////////////////////////////////////
    //                      SWAPS                        //
    ///////////////////////////////////////////////////////

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
    ) external payable nonReentrantWithFlags(SINGLE_POOL_SWAP_GUARD_FLAG) returns (uint256 amountIn, uint256 amountOut) {
        _validateDeadline(swapOrder.deadline);
        _validateRecipient(swapOrder.recipient);
        _validateExchangeFee(exchangeFee);
        _validateFeeOnTop(feeOnTop);

        InternalSwapCache memory swapCache;

        _initializeSwapCache(swapOrder, swapCache, exchangeFee, feeOnTop, transferData, 1);
        
        swapCache.poolId = poolId;
        
        uint256 tokenOutHookDataLength = swapHooksExtraData.tokenOutHook.length;
        uint256 poolHookDataLength = swapHooksExtraData.poolHook.length;

        swapCache.hookLongestData = swapHooksExtraData.tokenInHook.length;
        if (tokenOutHookDataLength > swapCache.hookLongestData) {
            swapCache.hookLongestData = tokenOutHookDataLength;
        }
        if (poolHookDataLength > swapCache.hookLongestData) {
            swapCache.hookLongestData = poolHookDataLength;
        }

        if (swapCache.inputSwap) {
            _poolSwapByInput(swapCache, true, swapHooksExtraData);
        } else {
            _poolSwapByOutput(swapCache, true, swapHooksExtraData);
        }

        _finalizeSwapCollectFundsAndDisburse(swapOrder, swapCache, exchangeFee, feeOnTop, transferData);
        (amountIn, amountOut) = (swapCache.amountIn, swapCache.amountOut);
    }

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
    ) external payable nonReentrantWithFlags(MULTI_POOL_SWAP_GUARD_FLAG) returns (uint256 amountIn, uint256 amountOut) {
        _validateDeadline(swapOrder.deadline);
        _validateRecipient(swapOrder.recipient);
        _validateExchangeFee(exchangeFee);
        _validateFeeOnTop(feeOnTop);

        if (poolIds.length == 0) {
            revert LBAMM__NoPoolsProvidedForMultiswap();
        }

        if (poolIds.length != swapHooksExtraDatas.length) {
            revert LBAMM__InvalidExtraDataArrayLength();
        }

        InternalSwapCache memory swapCache;
        unchecked {
            for (uint256 i = 0; i < swapHooksExtraDatas.length; ++i) {
                SwapHooksExtraData calldata swapHooksExtraData = swapHooksExtraDatas[i];
                uint256 tokenInHookDataLength = swapHooksExtraData.tokenInHook.length;
                uint256 tokenOutHookDataLength = swapHooksExtraData.tokenOutHook.length;
                uint256 poolHookDataLength = swapHooksExtraData.poolHook.length;
                if (tokenInHookDataLength > swapCache.hookLongestData) {
                    swapCache.hookLongestData = tokenInHookDataLength;
                }
                if (tokenOutHookDataLength > swapCache.hookLongestData) {
                    swapCache.hookLongestData = tokenOutHookDataLength;
                }
                if (poolHookDataLength > swapCache.hookLongestData) {
                    swapCache.hookLongestData = poolHookDataLength;
                }
            }
        }

        uint256 poolIdsLength = poolIds.length;
        _initializeSwapCache(swapOrder, swapCache, exchangeFee, feeOnTop, transferData, poolIdsLength);

        function (InternalSwapCache memory, bool, SwapHooksExtraData calldata) swapFunction = 
            swapCache.inputSwap ? _poolSwapByInput : _poolSwapByOutput;

        for (uint256 i = 0; i < poolIdsLength; ++i) {
            swapCache.hopIndex = i;
            swapCache.poolId = poolIds[i];
            swapFunction(swapCache, false, swapHooksExtraDatas[i]);
        }

        _finalizeSwapCollectFundsAndDisburse(swapOrder, swapCache, exchangeFee, feeOnTop, transferData);
        (amountIn, amountOut) = (swapCache.amountIn, swapCache.amountOut);
    }

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
    ) external payable nonReentrantWithFlags(DIRECT_SWAP_GUARD_FLAG) returns (uint256 amountIn, uint256 amountOut) {
        _validateDeadline(swapOrder.deadline);
        _validateRecipient(swapOrder.recipient);
        _validateExchangeFee(exchangeFee);
        _validateFeeOnTop(feeOnTop);

        if (swapHooksExtraData.poolHook.length > 0 || swapHooksExtraData.poolType.length > 0) {
            revert LBAMM__PoolHookDataNotSupported();
        }

        InternalSwapCache memory swapCache;
        {
            uint256 tokenInHookDataLength = swapHooksExtraData.tokenInHook.length;
            uint256 tokenOutHookDataLength = swapHooksExtraData.tokenOutHook.length;

            _initializeSwapCache(swapOrder, swapCache, exchangeFee, feeOnTop, transferData, 1);

            if (tokenInHookDataLength > swapCache.hookLongestData) {
                swapCache.hookLongestData = tokenInHookDataLength;
            }
            if (tokenOutHookDataLength > swapCache.hookLongestData) {
                swapCache.hookLongestData = tokenOutHookDataLength;
            }
        }
        swapCache.tokenIn = swapOrder.tokenIn;
        swapCache.tokenOut = swapOrder.tokenOut;

        _directSwap(swapOrder, directSwapParams, swapCache, swapHooksExtraData);
        
        _finalizeDirectSwap(swapOrder, directSwapParams, swapCache, exchangeFee, feeOnTop, transferData);
        (amountIn, amountOut) = (swapCache.amountIn, swapCache.amountOut);
    }

    ///////////////////////////////////////////////////////
    //              LIQUIDITY MANAGEMENT                 //
    ///////////////////////////////////////////////////////

    /**
     * @notice Adds liquidity to a position by depositing tokens and collecting accumulated fees.
     *
     * @dev    Throws when the pool does not exist.
     *         Throws when pool type contract call reverts.
     *         Throws when deposit amounts are below minimum requirements.
     *         Throws when insufficient fee balance available for fee collection.
     *         Throws when token debt storage causes overflow.
     *         Throws when any hook validation fails.
     *
     *         Delegates liquidity addition to the pool type contract, updates pool state, handles
     *         token transfers for deposits and fee collection, and executes all applicable hooks.
     *
     *         <h4>Developer Notes:</h4>
     *         - Net token amounts are calculated as deposit minus fees collected
     *         - Failed token transfers are gracefully handled by storing amounts as debt
     *         - Hook execution follows strict order: token hooks, position hooks, then pool hooks
     *
     *         <h4>Postconditions:</h4>
     *         1. Minimum deposit amounts validated against requirements
     *         2. Pool reserves increased by deposit amounts
     *         3. Pool fee balances reduced by fees collected
     *         4. Net token amounts collected from or distributed to provider
     *         5. All applicable hooks executed successfully
     *         6. Failed token transfers stored as debt rather than causing reverts
     *
     * @param  liquidityParams         Parameters for liquidity addition including pool ID and minimum amounts.
     * @param  liquidityHooksExtraData Hook data for token, position, and pool hook validations.
     * @return deposit0                Amount of token0 deposited into the pool.
     * @return deposit1                Amount of token1 deposited into the pool.
     * @return fees0                   Amount of token0 fees collected from the pool.
     * @return fees1                   Amount of token1 fees collected from the pool.
     */
    function addLiquidity(
        LiquidityModificationParams calldata liquidityParams,
        LiquidityHooksExtraData calldata liquidityHooksExtraData
    ) external payable delegateCallPure(MODULE_LIQUIDITY) returns (uint256 deposit0, uint256 deposit1, uint256 fees0, uint256 fees1) { }

    /**
     * @notice Removes liquidity from a position by withdrawing tokens and collecting accumulated fees.
     *
     * @dev    Throws when the pool does not exist.
     *         Throws when pool type contract call reverts.
     *         Throws when withdraw amounts are below minimum requirements.
     *         Throws when reserve or fee balance underflow occurs during reduction.
     *         Throws when token debt storage causes overflow.
     *         Throws when any hook validation fails.
     *
     *         Delegates liquidity removal to the pool type contract, updates pool state by reducing
     *         reserves and fee balances, distributes withdrawn tokens and collected fees to the position owner,
     *         and executes all applicable hooks.
     *
     *         <h4>Developer Notes:</h4>
     *         - Hook execution follows strict order: token hooks, position hooks, then pool hooks
     *
     *         <h4>Postconditions:</h4>
     *         1. Minimum withdraw amounts validated against requirements
     *         2. Pool state updated (reserves and fee balances reduced)
     *         3. Net token amounts distributed to position owner (withdraw + fees)
     *         4. All applicable hooks executed successfully
     *         5. Failed token transfers stored as debt rather than causing reverts
     *
     * @param  liquidityParams         Parameters for liquidity removal including pool ID and minimum amounts.
     * @param  liquidityHooksExtraData Hook data for token, position, and pool hook validations.
     * @return withdraw0               Amount of token0 withdrawn from the pool.
     * @return withdraw1               Amount of token1 withdrawn from the pool.
     * @return fees0                   Amount of token0 fees collected from the pool.
     * @return fees1                   Amount of token1 fees collected from the pool.
     */
    function removeLiquidity(
        LiquidityModificationParams calldata liquidityParams,
        LiquidityHooksExtraData calldata liquidityHooksExtraData
    ) external delegateCallPure(MODULE_LIQUIDITY)  returns (uint256 withdraw0, uint256 withdraw1, uint256 fees0, uint256 fees1) { }

    /**
     * @notice Collects accumulated fees from a liquidity position and distributes them to the provider.
     *
     * @dev    Throws when the pool does not exist.
     *         Throws when pool type contract call reverts.
     *         Throws when fee balance underflow occurs during reduction.
     *         Throws when SafeCast conversion fails (fees exceed uint128 max).
     *         Throws when token debt storage causes overflow.
     *         Throws when any hook validation fails.
     *
     *         This function collects fees that have accumulated on a liquidity position by delegating to the
     *         pool type contract for fee calculation, reducing pool fee balances, distributing collected fees
     *         to the liquidity provider, and executing all applicable hook validations.
     *
     *         <h4>Developer Notes:</h4>
     *         - Negative amounts passed to distribution function indicate outbound transfers to provider
     *         - Failed token transfers are gracefully handled by storing amounts as debt
     *         - Hook execution follows strict order: token hooks, position hooks, then pool hooks
     *
     *         <h4>Postconditions:</h4>
     *         1. Pool fee balances reduced by collected amounts
     *         2. Collected fees distributed to liquidity provider
     *         3. Token hooks executed for both tokens if enabled in token settings
     *         4. Position hook executed if liquidity hook address is non-zero
     *         5. Pool hook executed if pool hook address is non-zero
     *         6. LiquidityContext populated with caller, provider, and token information
     *         7. Failed token transfers stored as debt rather than causing reverts
     *
     * @param  liquidityParams         Parameters for fee collection including pool ID and pool-specific data.
     * @param  liquidityHooksExtraData Hook data for token, position, and pool hook validations.
     * @return fees0                   Amount of token0 fees collected and distributed to provider.
     * @return fees1                   Amount of token1 fees collected and distributed to provider.
     */
    function collectFees(
        LiquidityCollectFeesParams calldata liquidityParams,
        LiquidityHooksExtraData calldata liquidityHooksExtraData
    ) external delegateCallPure(MODULE_LIQUIDITY) returns (uint256 fees0, uint256 fees1) { }

    ///////////////////////////////////////////////////////
    //                 FEE COLLECTION                    //
    ///////////////////////////////////////////////////////

    /**
     * @notice Collects tokens owed to the caller from various fee distributions.
     *
     * @dev    Throws when token transfer fails.
     *         Throws when no tokens owed for specified address-token pairs.
     *
     *         Used to collect hook fees, failed transfer amounts, and other owed tokens accumulated
     *         for the caller across different operations.
     *
     *         <h4>Postconditions:</h4>
     *         1. All owed tokens transferred to caller
     *         2. Owed balances cleared in storage
     *         3. TokensClaimed events emitted for successful transfers
     *
     * @param  tokensOwed Array of token addresses to collect owed amounts for.
     */
    function collectTokensOwed(address[] calldata tokensOwed) external delegateCallPure(MODULE_FEE_COLLECTION) { }

    /**
     * @notice Allows hook contracts to collect their accumulated fees.
     *
     * @dev    Throws when caller is not the specified hook contract.
     *         Throws when requested amount exceeds available fees.
     *
     *         Used when token settings specify that hooks manage their own fees. Only the hook
     *         contract itself can call this function to collect its accumulated fees.
     *
     *         <h4>Postconditions:</h4>
     *         1. Hook fees transferred to specified recipient
     *         2. Fee balance reduced by collected amount
     *         3. TokensClaimed events emitted for successful transfers
     *
     * @param  tokenFor  The token address the fees are associated with.
     * @param  tokenFee  The token address being collected as fee payment.
     * @param  recipient Address to receive the collected fees.
     * @param  amount    Amount of fees to collect.
     */
    function collectHookFeesByHook(address tokenFor, address tokenFee, address recipient, uint256 amount)
        external delegateCallPure(MODULE_FEE_COLLECTION) { }

    /**
     * @notice Allows token administrators to collect hook fees for their tokens.
     *
     * @dev    Throws when caller lacks admin permissions for the token.
     *         Throws when requested amount exceeds available fees.
     *
     *         Used when token settings specify that tokens manage their own hook fees. Only the
     *         token contract or its admin can collect these fees.
     *
     *         <h4>Postconditions:</h4>
     *         1. Hook fees transferred to specified recipient
     *         2. Fee balance reduced by collected amount
     *         3. TokensClaimed events emitted for successful transfers
     *
     * @param  tokenFor  The token address the fees are associated with.
     * @param  tokenFee  The token address being collected as fee payment.
     * @param  recipient Address to receive the collected fees.
     * @param  amount    Amount of fees to collect.
     */
    function collectHookFeesByToken(address tokenFor, address tokenFee, address recipient, uint256 amount)
        external delegateCallPure(MODULE_FEE_COLLECTION) { }

    ///////////////////////////////////////////////////////
    //                   VIEW FUNCTIONS                  //
    ///////////////////////////////////////////////////////

    /**
     * @notice Retrieves the current state of a pool.
     *
     * @dev    Returns the complete pool state including tokens, pool hook, liquidity, and fee growth.
     *
     * @param  poolId The pool identifier.
     * @return state  The complete pool state.
     */
    function getPoolState(bytes32 poolId) external view delegateCallPureView(MODULE_LIQUIDITY) returns (PoolState memory state) { }

    /**
     * @notice Returns the hook settings and configuration for a specific token.
     *
     * @param  token         The token address to check.
     * @return tokenSettings The complete token settings including hop fee, token configuration and token hook address.
     */
    function getTokenSettings(address token) external view delegateCallPureView(MODULE_ADMIN) returns (TokenSettings memory tokenSettings) { }

    /**
     * @notice Returns the current flash loan fee rate.
     *
     * @return flashLoanBPS The flash loan fee rate in basis points.
     */
    function getFlashloanFeeBPS() external view delegateCallPureView(MODULE_FEE_COLLECTION) returns (uint16 flashLoanBPS) { }

    /**
     * @notice Returns the amount of tokens owed to a specific user.
     *
     * @param  user               The user's address.
     * @param  token              The token address.
     * @return tokensOwedAmount   The amount of tokens owed to the user.
     */
    function getTokensOwed(
        address user,
        address token
    ) external view delegateCallPureView(MODULE_FEE_COLLECTION) returns (uint256 tokensOwedAmount) { }

    /**
     * @notice Returns hook fees owed to a specific hook contract.
     *
     * @param  hook                  The hook contract address.
     * @param  tokenFor              The token the fees are associated with.
     * @param  tokenFee              The token being used for fee payment.
     * @return hookFeesOwedAmount    The amount of hook fees owed.
     */
    function getHookFeesOwedByHook(
        address hook,
        address tokenFor,
        address tokenFee
    ) external view delegateCallPureView(MODULE_FEE_COLLECTION) returns (uint256 hookFeesOwedAmount) { }

    /**
     * @notice Returns hook fees owed for a specific token.
     *
     * @param  tokenFor              The token the fees are associated with.
     * @param  tokenFee              The token being used for fee payment.
     * @return hookFeesOwedAmount    The amount of hook fees owed.
     */
    function getHookFeesOwedByToken(
        address tokenFor,
        address tokenFee
    ) external view delegateCallPureView(MODULE_FEE_COLLECTION) returns (uint256 hookFeesOwedAmount) { }

    /**
     * @notice Returns the current protocol fee structure.
     *
     * @return protocolFeeDetails The complete protocol fee configuration including lp fee, protocol fee and flat fee on top.
     */
    function getProtocolFeeStructure(
        address exchangeFeeRecipient,
        address feeOnTopFeeRecipient,
        bytes32 poolId
    ) external view delegateCallPureView(MODULE_FEE_COLLECTION) returns (ProtocolFeeStructure memory protocolFeeDetails) { }

    /**
     * @notice  Checks the AMM's execution state using reentrancy flags defined in Constants.sol.
     * 
     * @dev     Flag definitions allow varying granularity of checks from high level of 
     *          "AMM is executing an operation" to detailed "AMM is executing a single pool swap".
     */
    function checkAMMExecutionState(uint256 flags) 
        external view delegateCallPureView(MODULE_ADMIN) returns (bool) { }

    ///////////////////////////////////////////////////////
    //                   FLASH LOANS                     //
    ///////////////////////////////////////////////////////

    /**
     * @notice Executes a flash loan.
     *
     * @dev    Throws when flash loans are disabled.
     *         Throws when token hook validation fails.
     *         Throws when executor callback fails.
     *         Throws when insufficient tokens returned after callback execution.
     *
     *         Provides temporary access to protocol tokens with deferred payment requirements. Calculates
     *         fees using token hooks or default protocol rates, transfers loan amount to executor,
     *         executes callback function on executor contract, validates return of loan plus fees,
     *         and distributes fees between hook fees and protocol fees.
     *
     *         Supports cross-token fee payments where fees can be paid in a different token than the
     *         loan token, subject to fee token validation hooks. Handles surplus token returns by
     *         adding them to the total fee amount.
     *
     *         <h4>Postconditions:</h4>
     *         1. Loan amount transferred to executor contract
     *         2. Flashloan callback executed on executor with loan details
     *         3. Loan amount plus fees collected from executor
     *         4. Hook fees stored for later distribution to hook contracts
     *         5. Protocol fees stored for later collection
     *         6. Flashloan event emitted with operation details
     *
     * @param flashloanRequest Complete flash loan parameters including loan token, amount, executor address, callback data, and hook validation data.
     */
    function flashLoan(FlashloanRequest calldata flashloanRequest)
        external delegateCallPure(MODULE_LIQUIDITY) { }

    ///////////////////////////////////////////////////////
    //                 INTERNAL ROUTING                  //
    ///////////////////////////////////////////////////////

    /**
     * @notice  Called internally by Limit Break AMM after a swap is finalized to distribute
     *          queued hook fee transfers.
     */
    function executeQueuedHookFeesByHookTransfers() external delegateCallPure(MODULE_FEE_COLLECTION) { }

    ///////////////////////////////////////////////////////
    //                 PROTOCOL FUNCTIONS                //
    ///////////////////////////////////////////////////////

    /**
     * @notice Sets the protocol fee structure for swap and liquidity operations.
     *
     * @dev    Throws when `lpFeeBPS` exceeds the maximum allowed basis points.
     *         Throws when `exchangeFeeBPS` exceeds the maximum allowed basis points.
     *         Throws when `feeOnTopBPS` exceeds the maximum allowed basis points.
     *         Throws when the caller does not have the FEE_MANAGER role.
     *
     *         Protocol fees are collected from swaps and liquidity operations and distributed according to
     *         the specified structure. LP fees are taken from pool swap fees, while exchange fees and
     *         fees-on-top are applied to individual transactions.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee structure updated in storage.
     *         2. ProtocolFeesSet event emitted with the new fee structure.
     *
     * @param  protocolFeeStructure The protocol fee structure to set (see ProtocolFeeStructure).
     *                              - lpFeeBPS: The BPS fee collected from the LP fee.
     *                              - exchangeFeeBPS: The BPS fee collected for each swap.
     *                              - feeOnTopBPS: The BPS fee collected on top of the exchange fee.
     */
    function setProtocolFees(ProtocolFeeStructure memory protocolFeeStructure)
        external delegateCallPure(MODULE_ADMIN) { }

    /**
     * @notice Sets a protocol fee override for an exchange fee recipient.
     *
     * @dev    Throws when protocol fee BPS exceeds maximum allowed.
     *         Throws when caller lacks FEE_MANAGER role.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee override structure updated in storage
     *         2. ExchangeProtocolFeeOverrideSet event emitted with new fee override settings.
     * 
     * @param recipient           The recipient address to set an override for.
     * @param feeOverrideEnabled  True if the default fee is being overridden.
     * @param protocolFeeBPS      Fee rate in BPS to assess on a pool.
     */
    function setExchangeProtocolFeeOverride(address recipient, bool feeOverrideEnabled, uint256 protocolFeeBPS)
        external delegateCallPure(MODULE_ADMIN) { }

    /**
     * @notice Sets a protocol fee override for a fee on top fee recipient.
     *
     * @dev    Throws when protocol fee BPS exceeds maximum allowed.
     *         Throws when caller lacks FEE_MANAGER role.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee override structure updated in storage
     *         2. FeeOnTopProtocolFeeOverrideSet event emitted with new fee override settings.
     * 
     * @param recipient           The recipient address to set an override for.
     * @param feeOverrideEnabled  True if the default fee is being overridden.
     * @param protocolFeeBPS      Fee rate in BPS to assess on a pool.
     */
    function setFeeOnTopProtocolFeeOverride(address recipient, bool feeOverrideEnabled, uint256 protocolFeeBPS)
        external delegateCallPure(MODULE_ADMIN) { }

    /**
     * @notice Sets a protocol fee override for a fee on top fee recipient.
     *
     * @dev    Throws when protocol fee BPS exceeds maximum allowed.
     *         Throws when caller lacks FEE_MANAGER role.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee override structure updated in storage
     *         2. LPProtocolFeeOverrideSet event emitted with new fee override settings.
     * 
     * @param poolId              The pool identifier to set an override for.
     * @param feeOverrideEnabled  True if the default fee is being overridden.
     * @param protocolFeeBPS      Fee rate in BPS to assess on a pool.
     */
    function setLPProtocolFeeOverride(bytes32 poolId, bool feeOverrideEnabled, uint256 protocolFeeBPS)
        external delegateCallPure(MODULE_ADMIN) { }

    /**
     * @notice Sets the flash loan fee rate for the protocol.
     *
     * @dev    Throws when caller lacks FEE_MANAGER role.
     *
     *         Flash loan fees are collected as a percentage of the borrowed amount. Setting the fee
     *         above MAX_BPS effectively disables flash loans. The fee is applied in addition to any
     *         token-specific hook fees.
     *
     *         <h4>Postconditions:</h4>
     *         1. Flash loan fee rate updated in storage
     *         2. FlashloanFeeSet event emitted with new fee rate
     *
     * @param  flashLoanBPS The flash loan fee rate in basis points (>MAX_BPS disables flash loans).
     */
    function setFlashloanFee(uint256 flashLoanBPS) external delegateCallPure(MODULE_ADMIN) { }

    /**
     * @notice Sets hop fees for individual tokens across all operations.
     *
     * @dev    Throws when caller lacks FEE_MANAGER role.
     *         Throws when arrays have mismatched lengths.
     *         Throws when any hop fee exceeds maximum allowed.
     *
     *         Hop fees serve as token-specific protocol fees applied when swapping that token,
     *         providing additional revenue streams and potential usage controls for token projects.
     *
     *         <h4>Postconditions:</h4>
     *         1. Hop fee rates updated for all specified tokens
     *         2. TokenFeeSet event emitted for each token
     *
     * @param  tokens     Array of token addresses to configure.
     * @param  hopFeesBPS Array of hop fees in basis points for each corresponding token.
     */
    function setTokenFees(address[] calldata tokens, uint16[] calldata hopFeesBPS)
        external delegateCallPure(MODULE_ADMIN) { }

    /**
     * @notice Collects accumulated protocol fees for specified tokens.
     *
     * @dev    Throws when token transfer fails.
     *
     *         Transfers all accumulated protocol fees to the designated fee receiver role holder.
     *         Fees are cleared from storage after successful transfer to prevent double collection.
     *         Function is unrestricted as fees always go to the designated role holder regardless
     *         of caller identity, enabling automated collection systems.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fees transferred to fee receiver
     *         2. Fee balances cleared in storage
     *         3. ProtocolFeesCollected event emitted for each token
     *
     * @param  tokens Array of token addresses to collect protocol fees for.
     */
    function collectProtocolFees(address[] calldata tokens) external delegateCallPure(MODULE_ADMIN) { }

    /**
     * @notice Returns the amount of protocol fees accumulated for a specific token.
     *
     * @param  token The token address to check.
     * @return fees  The amount of accumulated protocol fees.
     */
    function getProtocolFees(address token) external view delegateCallPureView(MODULE_ADMIN) returns (uint256 fees) { }
}
