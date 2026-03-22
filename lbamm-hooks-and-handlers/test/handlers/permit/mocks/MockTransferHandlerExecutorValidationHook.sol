pragma solidity 0.8.24;

import "src/handlers/interfaces/ITransferHandlerExecutorValidation.sol";

contract TransferHandlerExecutorValidationHook is ITransferHandlerExecutorValidation {
    error TransferHandlerValidator_InvalidExecutor();

    mapping(address => bool) public validExecutors;
    
    function validateExecutor(
        bytes32 /* handlerId */,
        address executor,
        SwapOrder calldata /*swapOrder*/,
        uint256 /* amountIn */,
        uint256 /* amountOut */,
        BPSFeeWithRecipient calldata /* exchangeFee */,
        FlatFeeWithRecipient calldata /* feeOnTop */,
        bytes calldata /* hookData */
    ) external view {
        if (!validExecutors[executor]) {
            revert TransferHandlerValidator_InvalidExecutor();
        }
    }

    function setValidExecutor(address executor, bool isValid) external {
        validExecutors[executor] = isValid;
    }
}
