//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMTokenHook
 * @author Limit Break, Inc.
 * @notice Interface definition for token hooks to validate AMM operations involving the token.
 */
interface ILimitBreakAMMTokenHook {
    /// @dev Emitted when the token hook manifest URI is updated.
    event TokenHookManifestUriUpdated(string uri);

    /**
     * @notice  Informs the AMM of required and supported flags when the token hook is being
     *          set as the hook for a token.
     * 
     * @dev     A required flag is a flag that a token owner **MUST** enable.
     * @dev     A supported flag is a flag that a token owner **MAY** enable.
     * @dev     All required flags **MUST** be supported flags.
     * @dev     The AMM core will revert the token's hook setting operation if the token
     *          owner attempts to set a hook flag that is not supported or does not set
     *          a hook flag that is required.
     * 
     * @return requiredFlags   Bitmap of flags that **MUST** be enabled for the hook.
     * @return supportedFlags  Bitmap of flags that are supported by the hook.
     */
    function hookFlags() external view returns (uint32 requiredFlags, uint32 supportedFlags);

    /**
     * @notice  Validates a pool creation operation for the token.
     * 
     * @dev     Hooks **MUST** revert to prevent the pool from being created.
     * 
     * @param poolId         The identifier of the pool to validate.
     * @param creator        Address of the account calling the AMM to create the pool.
     * @param hookForToken0  True if the hook is being called for the token0 side of the pool.
     * @param details        Creation details for the pool.
     * @param hookData       Arbitrary calldata provided with the pool creation operation for the token hook.
     */
    function validatePoolCreation(
        bytes32 poolId,
        address creator,
        bool hookForToken0,
        PoolCreationDetails calldata details,
        bytes calldata hookData
    ) external;

    /**
     * @notice  Called before a swap operation involving the token to validate conditions and return a fee amount.
     * 
     * @dev     Fee amount returned will be a fee on the input token if it is an input-based swap or output token
     *          for an output-based swap.
     * 
     * @dev     Hooks **MAY** call the AMM during the hook operation to collect fees.
     *          All fee transfer collections will be queued to execute after the swap is finalized.
     * 
     * @dev     Hooks **MUST** revert to prevent the swap from executing.
     * 
     * @param context     Context data for a swap operation including executor, recipient, exchange and tokens.
     * @param swapParams  Swap parameters for the operation through the pool.
     * @param hookData    Arbitrary calldata provided with the operation for the token hook.
     * 
     * @return fee  The fee amount to be assessed in the AMM.
     */
    function beforeSwap(
        SwapContext calldata context,
        HookSwapParams calldata swapParams,
        bytes calldata hookData
    ) external returns (uint256 fee);

    /**
     * @notice  Called after a swap operation involving the token to validate conditions and return a fee amount.
     * 
     * @dev     Fee amount returned will be a fee on the output token if it is an input-based swap or input token
     *          for an output-based swap.
     * 
     * @dev     Hooks **MAY** call the AMM during the hook operation to collect fees.
     *          All fee transfer collections will be queued to execute after the swap is finalized.
     * 
     * @dev     Hooks **MUST** revert to prevent the swap from executing.
     * 
     * @param context     Context data for a swap operation including executor, recipient, exchange and tokens.
     * @param swapParams  Swap parameters for the operation through the pool.
     * @param hookData    Arbitrary calldata provided with the operation for the token hook.
     * 
     * @return fee  The fee amount to be assessed in the AMM.
     */
    function afterSwap(
        SwapContext calldata context,
        HookSwapParams calldata swapParams,
        bytes calldata hookData
    ) external returns (uint256 fee);

    /**
     * @notice  Validates an order that is being opened in a transfer handler.
     * 
     * @dev     This hook will not be called by the AMM directly, it will be called by transfer
     * @dev     handlers during order creation.
     * @dev     Hooks **MUST** revert to prevent the handler order from being created.
     * 
     * @param maker               Address of the order maker.
     * @param hookForTokenIn      True if the hook is being called for the input token.
     * @param tokenIn             Address of the input token for the order.
     * @param tokenOut            Address of the output token for the order.
     * @param amountIn            Amount of input token for the order.
     * @param amountOut           Amount of output token for the order.
     * @param handlerOrderParams  Encoded parameters of the handler order.
     * @param hookData            Arbitrary calldata provided with the operation to validate.
     */
    function validateHandlerOrder(
        address maker,
        bool hookForTokenIn,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata handlerOrderParams,
        bytes calldata hookData
    ) external;

    /**
     * @notice  Validates a fee collection operation.
     * 
     * @dev     Hooks **MUST** revert to prevent the fee collection from being finalized.
     * 
     * @dev     Hooks **MAY** collect a fee from the provider by returning non-zero values for `hookFee0`
     *          and `hookFee1`. Fees will be allocated to the hook or token depending on the token's settings.
     * 
     * @dev     Hooks **MAY** call the AMM during the hook operation to collect fees.
     *          All fee transfer collections will be queued to execute after the liquidity operation is finalized.
     * 
     * @param hookForToken0    True if the hook is being called for the token0 side of the pool.
     * @param context          Context data for the liquidity operation including provider, tokens and position identifier.
     * @param liquidityParams  Parameters for the fee collection operation.
     * @param fees0            Amount of token0 fees collected.
     * @param fees1            Amount of token1 fees collected.
     * @param hookData         Arbitrary calldata provided with the operation to validate.
     * @return hookFee0        Fees in token0 to take from the liquidity provider.
     * @return hookFee1        Fees in token1 to take from the liquidity provider.
     */
    function validateCollectFees(
        bool hookForToken0,
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
     *          and `hookFee1`. Fees will be allocated to the hook or token depending on the token's settings.
     * 
     * @dev     Hooks **MAY** call the AMM during the hook operation to collect fees.
     *          All fee transfer collections will be queued to execute after the liquidity operation is finalized.
     * 
     * @param hookForToken0    True if the hook is being called for the token0 side of the pool.
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
    function validateAddLiquidity(
        bool hookForToken0,
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
     *          and `hookFee1`. Fees will be allocated to the hook or token depending on the token's settings.
     * 
     * @dev     Hooks **MAY** call the AMM during the hook operation to collect fees.
     *          All fee transfer collections will be queued to execute after the liquidity operation is finalized.
     * 
     * @param hookForToken0    True if the hook is being called for the token0 side of the pool.
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
    function validateRemoveLiquidity(
        bool hookForToken0,
        LiquidityContext calldata context,
        LiquidityModificationParams calldata liquidityParams,
        uint256 withdraw0,
        uint256 withdraw1,
        uint256 fees0,
        uint256 fees1,
        bytes calldata hookData
    ) external returns (uint256 hookFee0, uint256 hookFee1);

    /**
     * @notice  Called before a flashloan is executed to provide validation and return a fee amount.
     * 
     * @dev     Hooks **MUST** revert to prevent a flashloan from executing.
     * 
     * @param requester   Address of the account that requested the flashloan.
     * @param loanToken   Address of the token that was flashloaned.
     * @param loanAmount  Amount of token flashloaned.
     * @param executor    Address of the flashloan callback contract to execute operations with the loan.
     * @param hookData    Arbitrary calldata provided to the token hook for the operation.
     * 
     * @return feeToken   Address of the token to collect fees in.
     * @return fee        Amount of fees to collect in the fee token.
     */
    function beforeFlashloan(
        address requester,
        address loanToken,
        uint256 loanAmount,
        address executor,
        bytes calldata hookData
    ) external returns (address feeToken, uint256 fee);

    /**
     * @notice  Called when another token specifies the token as the fee token in a flashloan to validate it is allowed.
     * 
     * @dev     Hook may revert or return false if the flashloan is not allowed to use the token as a fee token.
     * 
     * @param requester   Address of the account that requested the flashloan.
     * @param loanToken   Address of the token that was flashloaned.
     * @param loanAmount  Amount of token flashloaned.
     * @param feeToken    Address of the token to collect fees in.
     * @param feeAmount   Amount of fees to collect in the fee token.
     * @param executor    Address of the flashloan callback contract to execute operations with the loan.
     * @param hookData    Arbitrary calldata provided to the token hook for the operation.
     * 
     * @return allowed    True if the token may be used as the fee token in a flash loan.
     */
    function validateFlashloanFee(
        address requester,
        address loanToken,
        uint256 loanAmount,
        address feeToken,
        uint256 feeAmount,
        address executor,
        bytes calldata hookData
    ) external returns (bool allowed);

    /**
     * @notice  Returns the manifest URI for the token hook to provide app integrations with
     *          information necessary to process transactions that utilize the token hook.
     * 
     * @dev     Hook developers **MUST** emit a `TokenHookManifestUriUpdated` event if the URI
     *          changes.
     * 
     * @return  manifestUri  The URI for the hook manifest data. 
     */
    function tokenHookManifestUri() external view returns(string memory manifestUri);
}