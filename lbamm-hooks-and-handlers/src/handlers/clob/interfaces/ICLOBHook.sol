//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../interfaces/ITransferHandlerExecutorValidation.sol";

/**
 * @title  ICLOBHook
 * @author Limit Break, Inc.
 * @notice Interface definition for CLOB hook contracts to provide validation of order makers
 *         and takers (via `ITransferHandlerExecutorValidation`) on an order book.
 */
interface ICLOBHook is ITransferHandlerExecutorValidation {

    /**
     * @notice  Validates the maker of an order in an order book.
     * 
     * @dev     Hooks **MUST** revert to prevent the order from being added to the order book.
     * 
     * @param orderBookKey  Key value for the order book - hash of token in, token out and group key.
     * @param depositor     Address of the order maker depositing into the order book.
     * @param sqrtPriceX96  Current price as sqrt(price) * 2^96
     * @param orderAmount   The size of the order in the amount of input token.
     * @param hookData      Arbitrary calldata provided with the order for validation.
     */
    function validateMaker(
        bytes32 orderBookKey,
        address depositor,
        uint160 sqrtPriceX96,
        uint256 orderAmount,
        bytes calldata hookData
    ) external;
}