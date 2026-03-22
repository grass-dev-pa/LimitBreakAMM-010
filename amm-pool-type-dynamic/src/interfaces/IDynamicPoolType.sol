//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../DataTypes.sol";
import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMMPoolType.sol";

/**
 * @title  IDynamicPoolType
 * @author Limit Break, Inc.
 * @notice Interface definition for dynamic pool functions and events.
 */
interface IDynamicPoolType is ILimitBreakAMMPoolType {
    /// @dev Event emitted when a swap occurs in a dynamic pool, containing pool-specific details
    event DynamicPoolSwapDetails(
        address indexed amm,
        bytes32 indexed poolId,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    /// @dev Event emitted when liquidity is added to a dynamic pool position
    event DynamicPoolLiquidityAdded(
        address indexed amm,
        bytes32 indexed poolId,
        bytes32 indexed positionId,
        int128 liquidity,
        int24 tickLower,
        int24 tickUpper
    );

    /// @dev Event emitted when liquidity is removed from a dynamic pool position
    event DynamicPoolLiquidityRemoved(
        address indexed amm,
        bytes32 indexed poolId,
        bytes32 indexed positionId,
        int128 liquidity,
        int24 tickLower,
        int24 tickUpper
    );

    /**
     * @notice Retrieves the current state of a specific pool for the provided AMM contract.
     *
     * @dev    View function that returns the current state of the pool including fee growth,
     *         current price, tick, and liquidity. Returns default values if pool does not exist
     *
     * @param  amm                 AMM contract address that owns the pool.
     * @param  poolId              Pool identifier to query.
     * @return poolState           Current state of the pool including fee growth, price, tick, and liquidity.
     */
    function getPoolState(
        address amm,
        bytes32 poolId
    ) external view returns (DynamicPoolState memory poolState);

    /**
     * @notice Retrieves position information for a specific AMM contract and position ID.
     *
     * @dev    View function that returns position information including tick range, liquidity, and fee growth.
     *         Returns default values if position does not exist.
     *
     * @param  amm                 AMM contract address that owns the position.
     * @param  positionId          Position identifier to query.
     * @return positionInfo        Information about the position including tick range, liquidity, and fee growth.
     */
    function getPositionInfo(
        address amm,
        bytes32 positionId
    ) external view returns (DynamicPositionInfo memory positionInfo);

    /**
     * @notice Retrieves tick information for a specific AMM contract and tick index.
     *
     * @dev    View function that returns information about a specific tick including liquidity, fee growth, and initialization status.
     *         Returns default values if tick does not exist.
     *
     * @param  amm        AMM contract address that owns the pool.
     * @param  tick       Tick index to query.
     * @return tickInfo   Information about the tick including liquidity, fee growth, and initialization status.
     */
    function getTickInfo(
        address amm,
        bytes32 poolId,
        int24 tick
    ) external view returns (TickInfo memory tickInfo);
}
