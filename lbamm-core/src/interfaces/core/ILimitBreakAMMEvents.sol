//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/**
 * @title  ILimitBreakAMMEvents
 * @author Limit Break, Inc.
 * @notice Interface definition for AMM event emissions.
 */
interface ILimitBreakAMMEvents {
    /// @dev Emitted when a pool is created.
    event PoolCreated(
        address indexed poolType,
        address indexed token0,
        address indexed token1,
        bytes32 poolId,
        address poolHook
    );

    /// @dev Emitted when a token updates its settings.
    event TokenSettingsUpdated(address indexed token, address indexed tokenHook, uint32 packedSettings);

    /// @dev Emitted when a protocol fee is taken.
    event ProtocolFeeTaken(address indexed token, uint256 amount);

    /// @dev Emitted when a pool swap executes.
    event Swap(
        bytes32 indexed poolId,
        address indexed recipient,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut,
        uint256 lpFeeAmount
    );

    /// @dev Emitted when a direct swap executes.
    event DirectSwap(
        address indexed executor,
        address indexed recipient,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /// @dev Emitted when hook fees are claimed.
    event TokensClaimed(address indexed recipient, address indexed token, uint256 amount);

    /// @dev Emitted when a flashloan has been executed.
    event Flashloan(
        address indexed requester,
        address indexed executor,
        address indexed loanedToken,
        uint256 loanAmount,
        address feeToken,
        uint256 feeAmount
    );

    /// @dev Emitted when liquidity is added to a pool.
    event LiquidityAdded(
        bytes32 indexed poolId,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 fees0,
        uint256 fees1
    );

    /// @dev Emitted when liquidity is removed from a pool.
    event LiquidityRemoved(
        bytes32 indexed poolId,
        address indexed provider,
        uint256 amount0,
        uint256 amount1,
        uint256 fees0,
        uint256 fees1
    );

    /// @dev Emitted when fees are collected from a pool.
    event FeesCollected(
        bytes32 indexed poolId,
        address indexed provider,
        uint256 fees0,
        uint256 fees1
    );

    /// @dev Emitted when protocol fees are updated.
    event ProtocolFeesSet(uint16 lpFeeBPS, uint16 exchangeFeeBPS, uint16 feeOnTopBPS);

    /// @dev Emitted when flashloan fees are updated.
    event FlashloanFeeSet(uint16 flashLoanBPS);

    /// @dev Emitted when protocol fees are collected.
    event ProtocolFeesCollected(
        address indexed protocolFeeReceiver, address indexed token, uint256 protocolFeesCollected
    );

    /// @dev Emitted when a token hop fee is set.
    event TokenFeeSet(address indexed token, uint16 hopFeeBPS);

    /// @dev Emitted when protocol exchange fee overrides are set for a recipient.
    event ExchangeProtocolFeeOverrideSet(address recipient, bool feeOverrideEnabled, uint16 protocolFeeBPS);

    /// @dev Emitted when protocol fee on top fee overrides are set for a recipient.
    event FeeOnTopProtocolFeeOverrideSet(address recipient, bool feeOverrideEnabled, uint16 protocolFeeBPS);

    /// @dev Emitted when protocol LP fee overrides are set for a pool.
    event LPProtocolFeeOverrideSet(bytes32 poolId, bool feeOverrideEnabled, uint16 protocolFeeBPS);
}
