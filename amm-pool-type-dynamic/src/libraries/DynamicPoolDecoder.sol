//SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.24;

import "../Constants.sol";

/**
 * @title  DynamicPoolDecoder
 * @author Limit Break, Inc.
 * @notice Provides utilities for extracting encoded data from pool identifiers in dynamic pool types.
 * @dev    This library decodes fee rate and tick spacing values that are packed into the 32-byte pool ID.
 */
library DynamicPoolDecoder {
    /**
     * @notice Extracts the fee rate from a packed pool identifier.
     *
     * @dev    The fee is stored in bits 0-15 of the pool ID and is extracted using a right bit shift
     *         of 0 positions (POOL_ID_FEE_SHIFT). The fee is encoded as a uint16 value representing 
     *         basis points (BPS) where 10000 BPS equals 100%.
     *
     *         Valid fee range: 0-10000 BPS (0-100%).
     *
     * @param  poolId The 32-byte pool identifier containing the packed fee information.
     * @return fee    The fee rate in basis points extracted from bits 0-15 of the pool ID.
     */
    function getPoolFee(bytes32 poolId) internal pure returns (uint16 fee) {
        fee = uint16(uint256(poolId) >> POOL_ID_FEE_SHIFT);
    }

    /**
     * @notice Extracts the tick spacing from a packed pool identifier for dynamic pools.
     * 
     * @dev    The tick spacing is stored in bits 16-39 of the pool ID and is extracted using a right
     *         bit shift of 16 positions (POOL_ID_SPACING_SHIFT). This parameter determines the granularity 
     *         of price ticks in dynamic pools.
     *
     *         Valid range: MIN_TICK_SPACING (1) to MAX_TICK_SPACING (16384).
     *
     * @param  poolId      The 32-byte pool identifier containing the packed tick spacing information.
     * @return tickSpacing The tick spacing value extracted from bits 16-39 of the pool ID.
     */
    function getPoolTickSpacing(bytes32 poolId) internal pure returns (int24 tickSpacing) {
        tickSpacing = int24(int256(uint256(poolId) >> POOL_ID_SPACING_SHIFT));
    }
}
