//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../DataTypes.sol";
import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMMPoolType.sol";

/**
 * @title  ISingleProviderPoolType
 * @author Limit Break, Inc.
 * @notice Interface definition for single provider pool functions and events.
 */
interface ISingleProviderPoolType is ILimitBreakAMMPoolType {
    /// @dev Event emitted when a swap is executed in a single-provider pool.
    event SingleProviderPoolSwapDetails(
        bytes32 indexed poolId,
        uint256 sqrtPriceX96,
        uint256 liquidity
    );
}
