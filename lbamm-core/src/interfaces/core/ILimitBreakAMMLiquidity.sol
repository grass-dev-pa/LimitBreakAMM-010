//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMLiquidity
 * @author Limit Break, Inc.
 * @notice Interface definition for AMM core liquidity pool creation, state view, and liquidity
 *         management functions.
 */
interface ILimitBreakAMMLiquidity {
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
    ) external payable returns (bytes32 poolId, uint256 deposit0, uint256 deposit1);

    /**
     * @notice Retrieves the current state of a pool.
     *
     * @dev    Returns the complete pool state including tokens, pool hook, liquidity, and fee growth.
     *
     * @param  poolId The pool identifier.
     * @return state  The complete pool state.
     */
    function getPoolState(bytes32 poolId) external view returns (PoolState memory state);

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
    ) external payable returns (uint256 deposit0, uint256 deposit1, uint256 fees0, uint256 fees1);

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
    ) external returns (uint256 withdraw0, uint256 withdraw1, uint256 fees0, uint256 fees1);

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
    ) external returns (uint256 fees0, uint256 fees1);
}
