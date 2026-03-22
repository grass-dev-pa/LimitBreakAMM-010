//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../Constants.sol";
import "../DataTypes.sol";

/**
 * @title  Storage
 * @author Limit Break, Inc.
 * @notice Provides Diamond storage pattern utilities for the Limit Break AMM system.
 *
 * @dev    This library implements the Diamond standard storage pattern to ensure isolated, collision-free
 *         storage across multiple module contracts. It provides access to the main LBAMMStorage using a deterministic
 *         storage slot to maintain state consistency across multiple module contracts.
 */
library Storage {
    /**
     * @notice Returns the main storage slot for the Limit Break AMM.
     *
     * @dev    Uses assembly to access a deterministic storage slot that follows the Diamond standard storage
     *         pattern. This ensures storage isolation and prevents slot collisions across different module
     *         contracts within the Diamond proxy architecture.
     *
     * @dev    The storage slot is calculated using the `DIAMOND_STORAGE_LBAMM_VAULT` constant to ensure
     *         consistent access to the same storage location across all modules.
     *
     * @return diamondStorage The LBAMMStorage struct containing all persistent state for the AMM system.
     */
    function appStorage() internal pure returns (LBAMMStorage storage diamondStorage) {
        assembly {
            diamondStorage.slot := DIAMOND_STORAGE_LBAMM_VAULT
        }
    }
}
