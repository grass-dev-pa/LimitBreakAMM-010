//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMPoolHook
 * @author Limit Break, Inc.
 * @notice Interface definition for pool hooks to validate AMM operations involving the pool.
 */
interface ILimitBreakAMMPoolHook {
    /// @dev Emitted when the pool hook manifest URI is updated.
    event PoolHookManifestUriUpdated(string uri);

    /**
     * @notice  Validates a pool creation operation that specifies the hook contract as the pool hook.
     * 
     * @dev     Hooks **MUST** revert to prevent the pool from being created.
     * 
     * @param poolId    The identifier of the pool to validate.
     * @param creator   Address of the account calling the AMM to create the pool.
     * @param details   Creation details for the pool.
     * @param hookData  Arbitrary calldata provided with the pool creation operation for the pool hook.
     */
    function validatePoolCreation(
        bytes32 poolId,
        address creator,
        PoolCreationDetails calldata details,
        bytes calldata hookData
    ) external;

    /**
     * @notice  Executed for pools that are created with the dynamic fee value to retrieve the LP fee for the swap.
     * 
     * @dev     The pool fee **CANNOT** exceed 10,000 BPS for an input-based swap or 9,999 BPS for an output-based swap.
     * 
     * @param context        Context data for a swap operation including executor, recipient, exchange and tokens.
     * @param poolFeeParams  Swap parameters for the operation through the pool.
     * @param hookData       Arbitrary calldata provided with the operation for the pool hook.
     * 
     * @return poolFeeBPS    The pool fee for the swap operation in basis points.
     */
    function getPoolFeeForSwap(
        SwapContext calldata context,
        HookPoolFeeParams calldata poolFeeParams,
        bytes calldata hookData
    ) external returns (uint256 poolFeeBPS);

    /**
     * @notice  Validates a fee collection operation.
     * 
     * @dev     Hooks **MUST** revert to prevent the fee collection from being finalized.
     * 
     * @dev     Hooks **MAY** collect a fee from the provider by returning non-zero values for `hookFee0`
     *          and `hookFee1`. Fees will be allocated to the hook in the AMM and must be collected by the hook.
     * 
     * @dev     Hooks **MAY** call the AMM during the hook operation to collect fees.
     *          All fee transfer collections will be queued to execute after the liquidity operation is finalized.
     * 
     * @param context          Context data for the liquidity operation including provider, tokens and position identifier.
     * @param liquidityParams  Parameters for the fee collection operation.
     * @param fees0            Amount of token0 fees collected.
     * @param fees1            Amount of token1 fees collected.
     * @param hookData         Arbitrary calldata provided with the operation to validate.
     * @return hookFee0        Fees in token0 to take from the liquidity provider.
     * @return hookFee1        Fees in token1 to take from the liquidity provider.
     */
    function validatePoolCollectFees(
        LiquidityContext calldata context,
        LiquidityCollectFeesParams calldata liquidityParams,
        uint256 fees0,
        uint256 fees1,
        bytes calldata hookData
    ) external returns (uint256 hookFee0, uint256 hookFee1);

    /**
     * @notice  Validates a liquidity add operation.
     * 
     * @dev     Hooks **MUST** revert to prevent the liquidity add from being finalized.
     * 
     * @dev     Hooks **MAY** collect a fee from the provider by returning non-zero values for `hookFee0`
     *          and `hookFee1`. Fees will be allocated to the hook in the AMM and must be collected by the hook.
     * 
     * @dev     Hooks **MAY** call the AMM during the hook operation to collect fees.
     *          All fee transfer collections will be queued to execute after the liquidity operation is finalized.
     * 
     * @param context          Context data for the liquidity operation including provider, tokens and position identifier.
     * @param liquidityParams  Parameters for the add liquidity operation.
     * @param deposit0         Amount of token0 added as liquidity.
     * @param deposit1         Amount of token1 added as liquidity.
     * @param fees0            Amount of token0 fees collected.
     * @param fees1            Amount of token1 fees collected.
     * @param hookData         Arbitrary calldata provided with the operation to validate.
     * @return hookFee0        Fees in token0 to take from the liquidity provider.
     * @return hookFee1        Fees in token1 to take from the liquidity provider.
     */
    function validatePoolAddLiquidity(
        LiquidityContext calldata context,
        LiquidityModificationParams calldata liquidityParams,
        uint256 deposit0,
        uint256 deposit1,
        uint256 fees0,
        uint256 fees1,
        bytes calldata hookData
    ) external returns (uint256 hookFee0, uint256 hookFee1);

    /**
     * @notice  Validates a liquidity removal operation.
     * 
     * @dev     Hooks **MUST** revert to prevent the liquidity removal from being finalized.
     * 
     * @dev     Hooks **MAY** collect a fee from the provider by returning non-zero values for `hookFee0`
     *          and `hookFee1`. Fees will be allocated to the hook in the AMM and must be collected by the hook.
     * 
     * @dev     Hooks **MAY** call the AMM during the hook operation to collect fees.
     *          All fee transfer collections will be queued to execute after the liquidity operation is finalized.
     * 
     * @param context          Context data for the liquidity operation including provider, tokens and position identifier.
     * @param liquidityParams  Parameters for the remove liquidity operation.
     * @param withdraw0        Amount of token0 removed from liquidity.
     * @param withdraw1        Amount of token1 removed from liquidity.
     * @param fees0            Amount of token0 fees collected.
     * @param fees1            Amount of token1 fees collected.
     * @param hookData         Arbitrary calldata provided with the operation to validate.
     * @return hookFee0        Fees in token0 to take from the liquidity provider.
     * @return hookFee1        Fees in token1 to take from the liquidity provider.
     */
    function validatePoolRemoveLiquidity(
        LiquidityContext calldata context,
        LiquidityModificationParams calldata liquidityParams,
        uint256 withdraw0,
        uint256 withdraw1,
        uint256 fees0,
        uint256 fees1,
        bytes calldata hookData
    ) external returns (uint256 hookFee0, uint256 hookFee1);

    /**
     * @notice  Returns the manifest URI for the pool hook to provide app integrations with
     *          information necessary to process transactions that utilize the pool hook.
     * 
     * @dev     Hook developers **MUST** emit a `PoolHookManifestUriUpdated` event if the URI
     *          changes.
     * 
     * @return  manifestUri  The URI for the hook manifest data. 
     */
    function poolHookManifestUri() external view returns(string memory manifestUri);
}