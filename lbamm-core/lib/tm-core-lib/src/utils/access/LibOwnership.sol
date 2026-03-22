//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title LibOwnership
 * @author Limit Break, Inc.
 * @notice Provides ownership and role-based access control utilities for token contract interactions.
 * @dev    This library offers gas-efficient, fallback-safe methods for checking ownership and role permissions
 *         on external token contracts. It supports both traditional ownership patterns and OpenZeppelin's
 *         AccessControl role-based permissions, with safe calling mechanisms that handle unimplemented functions gracefully.
 */
library LibOwnership {

    /// @dev The default admin role identifier used in OpenZeppelin AccessControl
    bytes32 private constant DEFAULT_ACCESS_CONTROL_ADMIN_ROLE = 0x00;

    /// @dev Throws when the caller is not the token contract, owner, or default admin
    error Ownership__CallerIsNotTokenOrOwnerOrAdmin();

    /// @dev Throws when the caller is not the token contract, owner, default admin, or specified role holder
    error Ownership__CallerIsNotTokenOrOwnerOrAdminOrRole();

    /**
     * @notice Reverts the transaction if the caller is not the token contract, owner, or default admin.
     *
     * @dev    Throws when the caller is neither the token contract itself, nor the owner, nor assigned the 
     *         default admin role.
     *
     * @dev    This function checks permissions in order of preference: token contract itself, contract owner,
     *         then default admin role. It uses safe calling mechanisms to handle contracts that may not
     *         implement ownership or role-based access control patterns.
     *
     * @param  tokenAddress The contract address of the token to check permissions for.
     */
    function requireCallerIsTokenOrContractOwnerOrAdmin(address tokenAddress) internal view {
        if (msg.sender == tokenAddress) {
            return;
        }

        (address contractOwner,) = safeOwner(tokenAddress);
        if (msg.sender == contractOwner) {
            return;
        }

        (bool callerIsContractAdmin,) = safeHasRole(tokenAddress, DEFAULT_ACCESS_CONTROL_ADMIN_ROLE, msg.sender);
        if (callerIsContractAdmin) {
            return;
        }

        revert Ownership__CallerIsNotTokenOrOwnerOrAdmin();
    }

    /**
     * @notice Reverts the transaction if the caller is not the token contract, owner, or default admin.
     *
     * @dev    Throws when the caller is neither the token contract itself, nor the owner, nor assigned the 
     *         default admin role.
     *
     * @dev    This function checks permissions in order of preference: token contract itself, contract owner,
     *         then default admin role. It uses safe calling mechanisms to handle contracts that may not
     *         implement ownership or role-based access control patterns.
     *
     * @param  caller       The contract using this library is responsibile for determining the _msgSender() and passing
     *                      it as the caller.
     * @param  tokenAddress The contract address of the token to check permissions for.
     */
    function requireCallerIsTokenOrContractOwnerOrAdmin(address caller, address tokenAddress) internal view {
        if (caller == tokenAddress) {
            return;
        }

        (address contractOwner,) = safeOwner(tokenAddress);
        if (caller == contractOwner) {
            return;
        }

        (bool callerIsContractAdmin,) = safeHasRole(tokenAddress, DEFAULT_ACCESS_CONTROL_ADMIN_ROLE, caller);
        if (callerIsContractAdmin) {
            return;
        }

        revert Ownership__CallerIsNotTokenOrOwnerOrAdmin();
    }

    /**
     * @notice Returns whether the caller is the token contract, owner, or default admin.
     *
     * @dev    Performs the same permission checks as requireCallerIsTokenOrContractOwnerOrAdmin but returns
     *         a boolean result instead of reverting. Uses safe calling mechanisms to handle contracts that
     *         may not implement ownership or role-based access control patterns.
     *
     * @param  caller              The address to check permissions for.
     * @param  tokenAddress        The contract address of the token to check permissions against.
     * @return isTokenOwnerOrAdmin True if caller has sufficient permissions, false otherwise.
     */
    function isCallerTokenOrContractOwnerOrAdmin(
        address caller,
        address tokenAddress
    ) internal view returns (bool isTokenOwnerOrAdmin) {
        if (caller == tokenAddress) {
            return true;
        }

        (address contractOwner,) = safeOwner(tokenAddress);
        if (caller == contractOwner) {
            return true;
        }

        (bool callerIsContractAdmin,) = safeHasRole(tokenAddress, DEFAULT_ACCESS_CONTROL_ADMIN_ROLE, caller);
        return callerIsContractAdmin;
    }

    /**
     * @notice Reverts the transaction if the caller lacks token, ownership, admin, or specified role permissions.
     *
     * @dev    Throws when the caller is neither the token contract itself, nor the owner, nor assigned the default admin role, nor holds the specified role.
     *
     * @dev    This function extends the basic permission checking to include custom role validation.
     *         It checks permissions in order: token contract itself, contract owner, default admin role,
     *         then the specified custom role. Uses safe calling mechanisms for fallback protection.
     *
     * @param  tokenAddress The contract address of the token to check permissions for.
     * @param  role         The custom role identifier to check in addition to standard permissions.
     */
    function requireCallerIsTokenOrContractOwnerOrAdminOrRole(address tokenAddress, bytes32 role) internal view {        
        if (msg.sender == tokenAddress) {
            return;
        }

        (address contractOwner,) = safeOwner(tokenAddress);
        if (msg.sender == contractOwner) {
            return;
        }

        (bool callerIsContractAdmin,) = safeHasRole(tokenAddress, DEFAULT_ACCESS_CONTROL_ADMIN_ROLE, msg.sender);
        if (callerIsContractAdmin) {
            return;
        }

        (bool callerHasRole,) = safeHasRole(tokenAddress, role, msg.sender);
        if (callerHasRole) {
            return;
        }

        revert Ownership__CallerIsNotTokenOrOwnerOrAdminOrRole();
    }

    /**
     * @notice Reverts the transaction if the caller lacks token, ownership, admin, or specified role permissions.
     *
     * @dev    Throws when the caller is neither the token contract itself, nor the owner, nor assigned the default admin role, nor holds the specified role.
     *
     * @dev    This function extends the basic permission checking to include custom role validation.
     *         It checks permissions in order: token contract itself, contract owner, default admin role,
     *         then the specified custom role. Uses safe calling mechanisms for fallback protection.
     *
     * @param  caller       The contract using this library is responsibile for determining the _msgSender() and passing
     *                      it as the caller.
     * @param  tokenAddress The contract address of the token to check permissions for.
     * @param  role         The custom role identifier to check in addition to standard permissions.
     */
    function requireCallerIsTokenOrContractOwnerOrAdminOrRole(address caller, address tokenAddress, bytes32 role) internal view {        
        if (caller == tokenAddress) {
            return;
        }

        (address contractOwner,) = safeOwner(tokenAddress);
        if (caller == contractOwner) {
            return;
        }

        (bool callerIsContractAdmin,) = safeHasRole(tokenAddress, DEFAULT_ACCESS_CONTROL_ADMIN_ROLE, caller);
        if (callerIsContractAdmin) {
            return;
        }

        (bool callerHasRole,) = safeHasRole(tokenAddress, role, caller);
        if (callerHasRole) {
            return;
        }

        revert Ownership__CallerIsNotTokenOrOwnerOrAdminOrRole();
    }

    /**
     * @notice Gas-efficient, fallback-safe method to retrieve the owner of a token contract.
     *
     * @dev    Attempts to call the owner() function on the target contract using assembly for gas efficiency.
     *         If the function is unimplemented or the call fails, the presence of a fallback function will
     *         not result in halted execution. The function uses the standard Ownable interface selector (0x8da5cb5b).
     *
     * @param  tokenAddress The address of the token contract to query for ownership.
     * @return owner        The owner address if the call succeeded, address(0) if it failed.
     * @return isError      True if there was an error retrieving the owner, false if successful.
     */
    function safeOwner(
        address tokenAddress
    ) private view returns(address owner, bool isError) {
        assembly ("memory-safe") {
            function _callOwner(_tokenAddress) -> _owner, _isError {
                mstore(0x00, 0x8da5cb5b)
                if and(iszero(lt(returndatasize(), 0x20)), staticcall(gas(), _tokenAddress, 0x1C, 0x04, 0x00, 0x20)) {
                    _owner := mload(0x00)
                    leave
                }
                _isError := true
            }
            owner, isError := _callOwner(tokenAddress)
        }
    }
    
    /**
     * @notice Gas-efficient, fallback-safe method to check role permissions on a token contract.
     *
     * @dev    Attempts to call the hasRole(bytes32,address) function on the target contract using assembly
     *         for gas efficiency. If the function is unimplemented or the call fails, the presence of a
     *         fallback function will not result in halted execution. Uses the standard AccessControl
     *         interface selector (0x91d14854).
     *
     * @param  tokenAddress The address of the token contract to query for role permissions.
     * @param  role         The role identifier to check permissions for.
     * @param  account      The address to check role permissions against.
     * @return hasRole      True if the account has the role and the call succeeded, false otherwise.
     * @return isError      True if there was an error in the call, false if successful.
     */
    function safeHasRole(
        address tokenAddress,
        bytes32 role,
        address account
    ) private view returns(bool hasRole, bool isError) {
        assembly ("memory-safe") {
            function _callHasRole(_tokenAddress, _role, _account) -> _hasRole, _isError {
                let ptr := mload(0x40)
                mstore(0x40, add(ptr, 0x60))
                mstore(ptr, 0x91d14854)
                mstore(add(0x20, ptr), _role)
                mstore(add(0x40, ptr), _account)
                if and(iszero(lt(returndatasize(), 0x20)), staticcall(gas(), _tokenAddress, add(ptr, 0x1C), 0x44, 0x00, 0x20)) {
                    _hasRole := mload(0x00)
                    leave
                }
                _isError := true
            }
            hasRole, isError := _callHasRole(tokenAddress, role, account)
        }
    }
}