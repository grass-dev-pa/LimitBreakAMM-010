//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@limitbreak/lb-amm-core/src/DataTypes.sol";

/**
 * @title  ITransferHandlerExecutorValidation
 * @author Limit Break, Inc.
 * @notice Interface definition for transfer handler hook contracts to provide validation of 
 *         order executors.
 */
interface ITransferHandlerExecutorValidation {

    /**
     * @notice  Validates the executor of a swap through a transfer handler.
     * 
     * @dev     Hooks **MUST** revert to prevent the execution from proceeding.
     * 
     * @param handlerId    An identifier from the transfer handler that can link back to 
     * @param executor     Address of the executor of the swap.
     * @param swapOrder    The swap order details containing deadline, recipient, amount specified, limit amount, and token addresses.
     * @param amountIn     The amount of input tokens for the execution.
     * @param amountOut    The amount of output tokens for the execution.
     * @param exchangeFee  Exchange fee configuration and recipient address.
     * @param feeOnTop     Additional flat fee configuration and recipient address.
     * @param hookData     Arbitrary calldata provided with the order for validation. 
     */
    function validateExecutor(
        bytes32 handlerId,
        address executor,
        SwapOrder calldata swapOrder,
        uint256 amountIn,
        uint256 amountOut,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        bytes calldata hookData
    ) external;
}