//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/**
 * @dev This struct contains the parameters for a fill-or-kill permit transfer that must be executed atomically.
 * 
 * @dev **permitProcessor**: The address of the permit processor contract handling the transfer.
 * @dev **from**: The address that is granting the permit and from which tokens will be transferred.
 * @dev **nonce**: A unique number used to prevent replay attacks and ensure permit uniqueness.
 * @dev **permitAmount**: The exact amount of tokens that must be transferred.
 * @dev **expiration**: The timestamp after which this permit becomes invalid and cannot be executed.
 * @dev **signature**: The EIP-712 signature proving authorization from the `from` address.
 * @dev **cosigner**: Address of the cosigner for the permit, cosignature must be valid if the address is non-zero.
 * @dev **cosignatureExpiration**: The timestamp at which the cosignature will become invalid.
 * @dev **cosignature**: The EIP-712 signature proving the executor is allowed to execute the permit.
 * @dev **hook**: A hook address for a contract that implements ITransferHandlerExecutorValidation to validate executors.
 * @dev **hookData**: Arbitrary calldata provided with the order for validation.
 */
struct FillOrKillPermitTransfer {
    address permitProcessor;
    address from;
    uint256 nonce;
    uint256 permitAmount;
    uint256 expiration;
    bytes signature;
    address cosigner;
    uint256 cosignatureExpiration;
    bytes cosignature;
    address hook;
    bytes hookData;
}

/**
 * @dev This struct contains the parameters for a partial fill permit transfer that supports incremental execution.
 * 
 * @dev **permitProcessor**: The address of the permit processor contract handling the transfer.
 * @dev **from**: The address that is granting the permit and from which tokens will be transferred.
 * @dev **salt**: A unique value used to prevent replay attacks and ensure permit uniqueness across partial fills.
 * @dev **permitAmountSpecified**: The amount specified for this partial fill (can be positive or negative).
 * @dev **permitLimitAmount**: The maximum cumulative amount that can be transferred across all partial fills.
 * @dev **expiration**: The timestamp after which this permit becomes invalid and cannot be executed.
 * @dev **signature**: The EIP-712 signature proving authorization from the `from` address.
 * @dev **cosigner**: Address of the cosigner for the permit, cosignature must be valid if the address is non-zero.
 * @dev **cosignatureExpiration**: The timestamp at which the cosignature will become invalid.
 * @dev **cosignatureNonce**: The nonce for the cosignature to prevent reuse.
 * @dev **cosignature**: The EIP-712 signature proving the executor is allowed to execute the permit.
 * @dev **hook**: A hook address for a contract that implements ITransferHandlerExecutorValidation to validate executors.
 * @dev **hookData**: Arbitrary calldata provided with the order for validation.
 */
struct PartialFillPermitTransfer {
    address permitProcessor;
    address from;
    uint256 salt;
    int256 permitAmountSpecified;
    uint256 permitLimitAmount;
    uint256 expiration;
    bytes signature;
    address cosigner;
    uint256 cosignatureExpiration;
    uint256 cosignatureNonce;
    bytes cosignature;
    address hook;
    bytes hookData;
}