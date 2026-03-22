pragma solidity 0.8.24;

import "src/handlers/clob/interfaces/ICLOBHook.sol";

contract MockClobValidationHook is ICLOBHook {
    error TransferHandlerValidator_InvalidExecutor();
    error TransferHandlerValidator_InvalidMaker();

    mapping(address => bool) public validExecutors;
    mapping(address => bool) public validMakers;

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

    function validateMaker(
        bytes32 /* orderBookKey */,
        address depositor,
        uint160 /* sqrtPriceX96 */,
        uint256 /* orderAmount */,
        bytes calldata /* hookData */
    ) external view {
        if (!validMakers[depositor]) {
            revert TransferHandlerValidator_InvalidMaker();
        }
    }

    function setValidExecutor(address executor, bool isValid) external {
        validExecutors[executor] = isValid;
    }

    function setValidMaker(address maker, bool isValid) external {
        validMakers[maker] = isValid;
    }
}
