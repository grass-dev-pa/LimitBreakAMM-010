//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../Constants.sol";

/**
 * @title  PoolDecoder
 * @author Limit Break, Inc.
 * @notice Provides utilities for extracting encoded data from pool identifiers in the LBAMM system.
 *
 * @dev    This library decodes various components packed into 32-byte pool IDs including fees, tick spacing,
 *         and hook addresses. Pool IDs use bit-packing to efficiently store multiple parameters in a single
 *         bytes32 value, and this library provides the extraction functions for those components.
 */
library PoolDecoder {
    /**
     * @notice Extracts the pool type address from a packed pool identifier.
     *
     * @dev    The pool type address is stored in bits 144-255 of the pool ID (112 bits total) and is extracted 
     *         using a right bit shift operation. Since addresses are normally 160 bits, this requires pool type 
     *         addresses to have at least 6 leading zero bytes to fit within the allocated bit space. 
     *         Uses assembly for gas optimization as this is a frequently called function.
     *
     * @param  poolId   The 32-byte pool identifier containing the packed pool type information.
     * @return poolType The pool type address extracted from the pool ID (truncated from full 160-bit address).
     */
    function getPoolType(bytes32 poolId) internal pure returns (address poolType) {
        assembly ("memory-safe") {
            poolType := shr(POOL_ID_TYPE_ADDRESS_SHIFT, poolId)
        }
    }

    /**
     * @notice Extracts the fee rate from a packed pool identifier.
     *
     * @dev    The fee is stored in bits 0-15 of the pool ID and is extracted using a right bit shift
     *         operation followed by casting to uint16. The fee is encoded as a uint16 value representing 
     *         basis points (BPS) where 10000 BPS equals 100%.
     *
     * @param  poolId The 32-byte pool identifier containing the packed fee information.
     * @return fee    The fee rate in basis points extracted from the pool ID.
     */
    function getPoolFee(bytes32 poolId) internal pure returns (uint16 fee) {
        fee = uint16(uint256(poolId) >> POOL_ID_FEE_SHIFT);
    }
}
