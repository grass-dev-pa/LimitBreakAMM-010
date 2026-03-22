//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMLiquidityHook
 * @author Limit Break, Inc.
 * @notice Interface definition for liquidity position hooks to validate a position's
 *         fee collection, add, and remove liquidity operations.
 */
interface ILimitBreakAMMLiquidityHook {
    /// @dev Emitted when the liquidity hook manifest URI is updated.
    event LiquidityHookManifestUriUpdated(string uri);

    /**
     * @notice  Validates a position's fee collection.
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
    function validatePositionCollectFees(
        LiquidityContext calldata context,
        LiquidityCollectFeesParams calldata liquidityParams,
        uint256 fees0,
        uint256 fees1,
        bytes calldata hookData
    ) external returns (uint256 hookFee0, uint256 hookFee1);

    /**
     * @notice  Validates a position's liquidity add.
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
    function validatePositionAddLiquidity(
        LiquidityContext calldata context,
        LiquidityModificationParams calldata liquidityParams,
        uint256 deposit0,
        uint256 deposit1,
        uint256 fees0,
        uint256 fees1,
        bytes calldata hookData
    ) external returns (uint256 hookFee0, uint256 hookFee1);

    /**
     * @notice  Validates a position's liquidity removal.
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
    function validatePositionRemoveLiquidity(
        LiquidityContext calldata context,
        LiquidityModificationParams calldata liquidityParams,
        uint256 withdraw0,
        uint256 withdraw1,
        uint256 fees0,
        uint256 fees1,
        bytes calldata hookData
    ) external returns (uint256 hookFee0, uint256 hookFee1);

    /**
     * @notice  Returns the manifest URI for the liquidity hook to provide app integrations with
     *          information necessary to process transactions that utilize the liquidity hook.
     * 
     * @dev     Hook developers **MUST** emit a `LiquidityHookManifestUriUpdated` event if the URI
     *          changes.
     * 
     * @return  manifestUri  The URI for the hook manifest data. 
     */
    function liquidityHookManifestUri() external view returns(string memory manifestUri);
}