//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./AMMModule.sol";

import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  ModuleLiquidity
 * @author Limit Break, Inc.
 * @notice Liquidity management module providing pool creation, add/remove liquidity, and flashloan capabilities for the Limit Break AMM.

 * @dev    This handles the complete lifecycle of liquidity positions including pool initialization,
 *         liquidity provision and withdrawal, accumulated fee collection, and temporary token access
 *         through flash loans.
 *
 *         Pool creation establishes new trading pairs with deterministic IDs and configurable parameters,
 *         while liquidity operations enable providers to deposit and withdraw tokens from existing pools.
 *         Fee collection allows providers to claim their share of trading fees without modifying their
 *         liquidity positions. Flash loans provide temporary access to protocol tokens for various
 *         DeFi operations that require upfront capital.
 *
 *         The module integrates with the comprehensive hook system, supporting token-level validations
 *         and fee collection while maintaining compatibility with custom transfer handlers for complex
 *         payment flows. All operations include robust fee management with support for exchange fees,
 *         fees-on-top, and protocol fee distribution.
 */
contract ModuleLiquidity is AMMModule {
    constructor(
        address wrappedNative_
    ) AMMModule(wrappedNative_) {}

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
    ) external payable nonReentrant returns (bytes32 poolId, uint256 deposit0, uint256 deposit1) {
        poolId = _createPool(details, token0HookData, token1HookData, poolHookData);

        if (liquidityData.length > MINIMUM_LIQUIDITY_DATA_LENGTH) {
            if (bytes4(liquidityData[0:4]) == this.addLiquidity.selector) {
                _clearReentrancyGuard();

                (bool success, bytes memory returnData) = address(this).delegatecall(liquidityData);
                if (!success) {
                    assembly ("memory-safe") {
                        revert(add(returnData, 0x20), mload(returnData))
                    }
                }

                PoolState storage ptrPoolState = Storage.appStorage().pools[poolId];
                (deposit0, deposit1) = (ptrPoolState.reserve0, ptrPoolState.reserve1);
                if (deposit0 | deposit1 == 0) {
                    revert LBAMM__PoolCreationWithLiquidityDidNotAddLiquidity();
                }
            } else {
                revert LBAMM__LiquidityDataDoesNotCallAddLiquidity();
            }
        } else {
            if (msg.value > 0) {
                revert LBAMM__ValueNotUsed();
            }
        }
    }

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
    ) external payable nonReentrantWithFlags(ADD_LIQUIDITY_GUARD_FLAG) returns (uint256 deposit0, uint256 deposit1, uint256 fees0, uint256 fees1) {
        (deposit0, deposit1, fees0, fees1) = _positionAddLiquidity(
            liquidityParams,
            liquidityHooksExtraData
        );
    }

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
    ) external nonReentrantWithFlags(REMOVE_LIQUIDITY_GUARD_FLAG) returns (uint256 withdraw0, uint256 withdraw1, uint256 fees0, uint256 fees1) {
        (withdraw0, withdraw1, fees0, fees1) = _positionRemoveLiquidity(
            liquidityParams,
            liquidityHooksExtraData
        );
    }

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
    ) external nonReentrantWithFlags(COLLECT_FEES_LIQUIDITY_GUARD_FLAG) returns (uint256 fees0, uint256 fees1) {
        (fees0, fees1) = _positionCollectFees(
            liquidityParams,
            liquidityHooksExtraData
        );
    }

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
    function flashLoan(FlashloanRequest calldata flashloanRequest) external nonReentrantWithFlags(FLASHLOAN_GUARD_FLAG) {
        _flashLoan(flashloanRequest);
    }

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
    function getPoolState(bytes32 poolId) external view returns (PoolState memory state) {
        state = Storage.appStorage().pools[poolId];
    }
}
