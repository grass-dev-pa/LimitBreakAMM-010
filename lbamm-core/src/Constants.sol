//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity ^0.8.24;

/*====================================================*/
/*                  TM AMM CONSTANTS                  */
/*====================================================*/
/// @dev The base storage slot for Limit Break AMM contract storage items.
bytes32 constant DIAMOND_STORAGE_LBAMM_VAULT = 0x0000000000000000000000000000000000000000000000000000000000009A1D;

/// @dev The base transient slot for queued hook fee collection.
bytes32 constant DIAMOND_STORAGE_QUEUED_FEE_COLLECT = 0x00000000000000000000000000000000000000009A1D00000000000000000000;

/// @dev Max BPS value used in BIPS and fee calculations.
uint256 constant MAX_BPS = 100_00;

/// @dev Double precision basis points (10,000%) used for complex fee calculations and ratios
uint256 constant DOUBLE_BPS = MAX_BPS * MAX_BPS;

/// @dev Flag for reentrancy guard to indicate that a swap is in process.
uint256 constant SWAP_GUARD_FLAG = 1 << 2;

/// @dev Flag for reentrancy guard to indicate that a pool swap is in process.
uint256 constant POOL_SWAP_GUARD_FLAG = 1 << 3 | SWAP_GUARD_FLAG;

/// @dev Flag for reentrancy guard to indicate that a single pool swap is in process.
uint256 constant SINGLE_POOL_SWAP_GUARD_FLAG = 1 << 4 | POOL_SWAP_GUARD_FLAG;

/// @dev Flag for reentrancy guard to indicate that a multi pool swap is in process.
uint256 constant MULTI_POOL_SWAP_GUARD_FLAG = 1 << 5 | POOL_SWAP_GUARD_FLAG;

/// @dev Flag for reentrancy guard to indicate that a direct swap is in process.
uint256 constant DIRECT_SWAP_GUARD_FLAG = 1 << 6 | SWAP_GUARD_FLAG;

/// @dev Flag for reentrancy guard to indicate that a liquidity operation is in process.
uint256 constant LIQUIDITY_GUARD_FLAG = 1 << 7;

/// @dev Flag for reentrancy guard to indicate that a add liquidity operation is in process.
uint256 constant ADD_LIQUIDITY_GUARD_FLAG = 1 << 8 | LIQUIDITY_GUARD_FLAG;

/// @dev Flag for reentrancy guard to indicate that a remove liquidity operation is in process.
uint256 constant REMOVE_LIQUIDITY_GUARD_FLAG = 1 << 9 | LIQUIDITY_GUARD_FLAG;

/// @dev Flag for reentrancy guard to indicate that a collect fees liquidity operation is in process.
uint256 constant COLLECT_FEES_LIQUIDITY_GUARD_FLAG = 1 << 10 | LIQUIDITY_GUARD_FLAG;

/// @dev Flag for reentrancy guard to indicate that a flashloan operation is in process.
uint256 constant FLASHLOAN_GUARD_FLAG = 1 << 11;

/// @dev Base amount of memory to allocate for optimized hook calls from AMM.
uint16 constant HOOK_ALLOCATION_BASE = 576;

/// @dev Base amount of memory to allocate for optimized transfer handler calls from AMM.
uint16 constant TRANSFER_HANDLER_ALLOCATION_BASE = 576;

/// @dev Minimum length of liquidity data during pool creation to enter liquidity addition.
uint16 constant MINIMUM_LIQUIDITY_DATA_LENGTH = 4;

/// @dev Constant value for key offset to distinguish a hook fee from liquidity in tokens owed mapping.
bytes32 constant TOKEN_MANAGED_HOOK_FEE = 0x000000000000000000000000000000000000000000000000000000000000007F;

/// @dev Constant value for key offset to distinguish a liquidity from hook fee in tokens owed mapping.
bytes32 constant LIQUIDITY_OWED = 0x0000000000000000000000000000000000000000000000000000000000000010;

/**************************************************************/
/*                           ROLES                            */
/**************************************************************/

/// @dev Role hash for managing protocol fee settings and rates.
bytes32 constant LBAMM_FEE_MANAGER_BASE_ROLE = keccak256("LBAMM_FEE_MANAGER_ROLE");

/// @dev Role hash for receiving protocol fee distributions.
bytes32 constant LBAMM_FEE_RECEIVER_BASE_ROLE = keccak256("LBAMM_FEE_RECEIVER_ROLE");

/// @dev Role that may be assigned on a token contract using role-based access control to allow hook fee collection.
bytes32 constant LBAMM_TOKEN_FEE_COLLECTOR_ROLE = keccak256("LBAMM_TOKEN_FEE_COLLECTOR_ROLE");

/// @dev Role that may be assigned on a token contract using role-based access control to allow hook configuration.
bytes32 constant LBAMM_TOKEN_SETTING_MANAGER_ROLE = keccak256("LBAMM_TOKEN_SETTING_MANAGER_ROLE");

/// @dev Sentinel value indicating dynamic fee calculation should be used instead of fixed fee
uint16 constant DYNAMIC_POOL_FEE_BPS = 55_555;

/// @dev poolId is a packed value of the pool type address, hash of creation details and pool-specific packed data.
/// @dev Bits   0 to 111 - pool type address (addresses must start with 6 leading zero bytes).
/// @dev Bits 112 to 207 - creation details hash.
/// @dev Bits 208 to 255 - pool-specific packed data.

/// @dev Bit shift position for pool type address in poolId.
uint8 constant POOL_ID_TYPE_ADDRESS_SHIFT = 144;

/// @dev Bit mask for the creation details hash in poolId.
bytes32 constant POOL_HASH_MASK = 0x0000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF000000000000;

/// @dev Bit mask for validating pool type meets leading zero bytes requirement (6)
uint160 constant POOL_TYPE_ADDRESS_MASK = uint160(0xFFffFfffFfff0000000000000000000000000000);

/// @dev Token setting flag enabling before-swap hook validation
uint16 constant TOKEN_SETTINGS_BEFORE_SWAP_HOOK_FLAG = 1 << 0;

/// @dev Token setting flag enabling after-swap hook validation
uint16 constant TOKEN_SETTINGS_AFTER_SWAP_HOOK_FLAG = 1 << 1;

/// @dev Token setting flag enabling add liquidity hook
uint16 constant TOKEN_SETTINGS_ADD_LIQUIDITY_HOOK_FLAG = 1 << 2;

/// @dev Token setting flag enabling remove liquidity hook
uint16 constant TOKEN_SETTINGS_REMOVE_LIQUIDITY_HOOK_FLAG = 1 << 3;

/// @dev Token setting flag enabling collect fees hook
uint16 constant TOKEN_SETTINGS_COLLECT_FEES_HOOK_FLAG = 1 << 4;

/// @dev Token setting flag enabling pool creation hook validation
uint16 constant TOKEN_SETTINGS_POOL_CREATION_HOOK_FLAG = 1 << 5;

/// @dev Token setting flag indicating hook contract manages its own fee collection
uint16 constant TOKEN_SETTINGS_HOOK_MANAGES_FEES_FLAG = 1 << 6;

/// @dev Token setting flag enabling flash loan operations for the token
uint16 constant TOKEN_SETTINGS_FLASHLOANS_FLAG = 1 << 7;

/// @dev Token setting flag enabling flash loan fee validation for cross-token fee payments
uint16 constant TOKEN_SETTINGS_FLASHLOANS_VALIDATE_FEE_FLAG = 1 << 8;

/// @dev Token setting flag enabling transfer handler order validation
uint16 constant TOKEN_SETTINGS_HANDLER_ORDER_VALIDATE_FLAG = 1 << 9;

/// @dev Composite bitmask containing all hook-related configuration flags
uint16 constant TOKEN_SETTINGS_HOOK_FLAGS_MASK = 
    TOKEN_SETTINGS_BEFORE_SWAP_HOOK_FLAG |
    TOKEN_SETTINGS_AFTER_SWAP_HOOK_FLAG | 
    TOKEN_SETTINGS_ADD_LIQUIDITY_HOOK_FLAG |
    TOKEN_SETTINGS_REMOVE_LIQUIDITY_HOOK_FLAG |
    TOKEN_SETTINGS_COLLECT_FEES_HOOK_FLAG | 
    TOKEN_SETTINGS_POOL_CREATION_HOOK_FLAG | 
    TOKEN_SETTINGS_HOOK_MANAGES_FEES_FLAG | 
    TOKEN_SETTINGS_FLASHLOANS_FLAG | 
    TOKEN_SETTINGS_FLASHLOANS_VALIDATE_FEE_FLAG | 
    TOKEN_SETTINGS_HANDLER_ORDER_VALIDATE_FLAG;

/// @dev Bit shift position for packing pool fee rate in poolId.
uint8 constant POOL_ID_FEE_SHIFT = 0;