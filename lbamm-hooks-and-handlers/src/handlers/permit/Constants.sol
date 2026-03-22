//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/// @dev Convenience to avoid magic numbers in bitmask logic
uint256 constant ZERO = 0;

/// @dev Convenience to avoid magic numbers in bitmask logic
uint256 constant ONE = 1;

/// @dev Constant value for bitshift of nonce to bucket for bitmap
uint256 constant NONCE_TO_BUCKET_SHIFT = 8;

/// @dev Boolean true value used in permit transfer data encoding
uint8 constant TRUE = 1;

/// @dev Boolean false value used in permit transfer data encoding
uint8 constant FALSE = 0;

/// @dev Identifier for fill-or-kill permit transfers that must be executed atomically
bytes1 constant FILL_OR_KILL_PERMIT = 0x00;

/// @dev Identifier for partial fill permit transfers that support incremental execution
bytes1 constant PARTIAL_FILL_PERMIT = 0x01;

/// @dev EIP-712 typehash stub for building permitted transfer approval typehashes
string constant PERMITTED_TRANSFER_APPROVAL_TYPEHASH_STUB = "PermitTransferFromWithAdditionalData(uint256 tokenType,address token,uint256 id,uint256 amount,uint256 nonce,address operator,uint256 expiration,uint256 masterNonce,";

/// @dev EIP-712 typehash stub for building permitted order approval typehashes
string constant PERMITTED_ORDER_APPROVAL_TYPEHASH_STUB = "PermitOrderWithAdditionalData(uint256 tokenType,address token,uint256 id,uint256 amount,uint256 salt,address operator,uint256 expiration,uint256 masterNonce,";

/// @dev EIP-712 typehash stub for extra data in permit approval typehashes
string constant PERMITTED_APPROVAL_TYPEHASH_EXTRADATA_STUB = "Swap swapData)";

/// @dev EIP-712 typehash stub for the swap extra data in permit approval typehashes
string constant SWAP_TYPEHASH_STUB = "Swap(bool partialFill,address recipient,int256 amountSpecified,uint256 limitAmount,address tokenOut,address exchangeFeeRecipient,uint16 exchangeFeeBPS,address cosigner,address hook)";

/// @dev EIP-712 typehash for swap data structure used in permit validation
bytes32 constant SWAP_TYPEHASH = keccak256(bytes(SWAP_TYPEHASH_STUB));

/// @dev EIP-712 typehash for permit cosignatures
bytes32 constant COSIGNATURE_TYPEHASH = keccak256("Cosignature(bytes permitSignature,uint256 cosignatureExpiration,uint256 cosignatureNonce,address executor)");

/// @dev EIP-712 typehash for cosignature self destruction
bytes32 constant COSIGNER_SELF_DESTRUCT_TYPEHASH = keccak256("CosignerDestruct(address cosigner)");

/// @dev Sentinel value to indicate a permit cosignature is allowed to be used until the order is filled or the cosignature expires
uint256 constant REUSABLE_COSIGNATURE_NONCE = 0;

/// @dev Mirror sentinel value for reusable cosignatures as fill or kill permits may only be filled one time.
uint256 constant FILL_OR_KILL_COSIGNATURE_NONCE = REUSABLE_COSIGNATURE_NONCE;