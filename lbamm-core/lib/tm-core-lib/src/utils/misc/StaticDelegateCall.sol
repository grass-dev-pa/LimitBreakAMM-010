//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract StaticDelegateCall {
    /// @dev thrown when a call is made to the static delegate call execute function that did not originate from self.
    error StaticDelegateCall__CallerIsNotSelf();
    
    /**
     * @notice Restricts function access to only the contract itself.
     *
     * @dev    Reverts if the caller is not the contract. Used to enforce internal-only entrypoints,
     *         particularly for protected delegate call operations.
     */
    modifier onlySelf() {
        if (msg.sender != address(this)) {
            revert StaticDelegateCall__CallerIsNotSelf();
        }
        _;
    }

    /**
     * @notice Initiates a static delegate call to a target contract through this contract.
     *
     * @dev    Wraps and encodes a call to `executeStaticDelegateCall` and performs a `staticcall` to itself.
     *         Ensures read-only execution context is preserved when accessing delegate logic.
     *
     * @param  target The target contract address to delegate the call to.
     * @param  data   The ABI-encoded call data to send to the delegate target.
     * @return results The raw returned data from the static delegate call.
     */
    function initiateStaticDelegateCall(
        address target,
        bytes calldata data
    ) external view returns (bytes memory) {
        bytes memory encodedCall = abi.encodeWithSelector(
            StaticDelegateCall.executeStaticDelegateCall.selector,
            target,
            data
        );

        (bool success, bytes memory results) = address(this).staticcall(encodedCall);
        if (!success) {
            assembly("memory-safe") {
                revert(add(0x20, results), mload(results))
            }
        }
        assembly ("memory-safe") {
            return(add(0x20, results), mload(results))
        }
    }

    /**
     * @notice Executes a static delegate call to a specified target contract.
     *
     * @dev    Must be invoked via `staticcall` from within `initiateStaticDelegateCall`. This function uses
     *         `delegatecall` to execute the given data in the context of the current contract's storage and code.
     *         It is protected by `onlySelf` to prevent external invocation.
     *
     * @param  target The contract address to delegate the call to.
     * @param  data   The ABI-encoded calldata to send to the delegate target.
     * @return results The raw data returned from the delegate call.
     */
    function executeStaticDelegateCall(
        address target,
        bytes calldata data
    ) external onlySelf returns (bytes memory) {
        (bool success, bytes memory results) = target.delegatecall(data);
        if (!success) {
            assembly("memory-safe") {
                revert(add(0x20, results), mload(results))
            }
        }
        return results;
    }
}