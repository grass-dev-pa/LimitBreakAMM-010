//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMProtocol
 * @author Limit Break, Inc.
 * @notice Interface definition for AMM core protocol management and view functions.
 */
interface ILimitBreakAMMProtocol {
    /**
     * @notice Returns the current protocol fee structure.
     *
     * @return protocolFeeDetails The complete protocol fee configuration including lp fee, protocol fee and flat fee on top.
     */
    function getProtocolFeeStructure(
        address exchangeFeeRecipient,
        address feeOnTopRecipient,
        bytes32 poolId
    ) external view returns (ProtocolFeeStructure memory protocolFeeDetails);

    /**
     * @notice Returns the amount of protocol fees accumulated for a specific token.
     *
     * @param  token The token address to check.
     * @return fees  The amount of accumulated protocol fees.
     */
    function getProtocolFees(address token) external view returns (uint256 fees);

    /**
     * @notice Sets the protocol fee structure for swap and liquidity operations.
     *
     * @dev    Throws when `lpFeeBPS` exceeds the maximum allowed basis points.
     *         Throws when `exchangeFeeBPS` exceeds the maximum allowed basis points.
     *         Throws when `feeOnTopBPS` exceeds the maximum allowed basis points.
     *         Throws when the caller does not have the FEE_MANAGER role.
     *
     *         Protocol fees are collected from swaps and liquidity operations and distributed according to
     *         the specified structure. LP fees are taken from pool swap fees, while exchange fees and
     *         fees-on-top are applied to individual transactions.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee structure updated in storage.
     *         2. ProtocolFeesSet event emitted with the new fee structure.
     *
     * @param  protocolFeeStructure The protocol fee structure to set (see ProtocolFeeStructure).
     *                              - lpFeeBPS: The BPS fee collected from the LP fee.
     *                              - exchangeFeeBPS: The BPS fee collected for each swap.
     *                              - feeOnTopBPS: The BPS fee collected on top of the exchange fee.
     */
    function setProtocolFees(ProtocolFeeStructure memory protocolFeeStructure) external;

    /**
     * @notice Sets a protocol fee override for an exchange fee recipient.
     *
     * @dev    Throws when protocol fee BPS exceeds maximum allowed.
     *         Throws when caller lacks FEE_MANAGER role.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee override structure updated in storage
     *         2. ExchangeProtocolFeeOverrideSet event emitted with new fee override settings.
     * 
     * @param recipient           The recipient address to set an override for.
     * @param feeOverrideEnabled  True if the default fee is being overridden.
     * @param protocolFeeBPS      Fee rate in BPS to assess on a pool.
     */
    function setExchangeProtocolFeeOverride(address recipient, bool feeOverrideEnabled, uint256 protocolFeeBPS) external;

    /**
     * @notice Sets a protocol fee override for a fee on top fee recipient.
     *
     * @dev    Throws when protocol fee BPS exceeds maximum allowed.
     *         Throws when caller lacks FEE_MANAGER role.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee override structure updated in storage
     *         2. FeeOnTopProtocolFeeOverrideSet event emitted with new fee override settings.
     * 
     * @param recipient           The recipient address to set an override for.
     * @param feeOverrideEnabled  True if the default fee is being overridden.
     * @param protocolFeeBPS      Fee rate in BPS to assess on a pool.
     */
    function setFeeOnTopProtocolFeeOverride(address recipient, bool feeOverrideEnabled, uint256 protocolFeeBPS) external;

    /**
     * @notice Sets a protocol fee override for a fee on top fee recipient.
     *
     * @dev    Throws when protocol fee BPS exceeds maximum allowed.
     *         Throws when caller lacks FEE_MANAGER role.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee override structure updated in storage
     *         2. LPProtocolFeeOverrideSet event emitted with new fee override settings.
     * 
     * @param poolId              The pool identifier to set an override for.
     * @param feeOverrideEnabled  True if the default fee is being overridden.
     * @param protocolFeeBPS      Fee rate in BPS to assess on a pool.
     */
    function setLPProtocolFeeOverride(bytes32 poolId, bool feeOverrideEnabled, uint256 protocolFeeBPS) external;

    /**
     * @notice Sets the flash loan fee rate for the protocol.
     *
     * @dev    Throws when caller lacks FEE_MANAGER role.
     *
     *         Flash loan fees are collected as a percentage of the borrowed amount. Setting the fee
     *         above MAX_BPS effectively disables flash loans. The fee is applied in addition to any
     *         token-specific hook fees.
     *
     *         <h4>Postconditions:</h4>
     *         1. Flash loan fee rate updated in storage
     *         2. FlashloanFeeSet event emitted with new fee rate
     *
     * @param  flashLoanBPS The flash loan fee rate in basis points (>MAX_BPS disables flash loans).
     */
    function setFlashloanFee(uint256 flashLoanBPS) external;

    /**
     * @notice Sets hop fees for individual tokens across all operations.
     *
     * @dev    Throws when caller lacks FEE_MANAGER role.
     *         Throws when arrays have mismatched lengths.
     *         Throws when any hop fee exceeds maximum allowed.
     *
     *         Hop fees serve as token-specific protocol fees applied when swapping that token,
     *         providing additional revenue streams and potential usage controls for token projects.
     *
     *         <h4>Postconditions:</h4>
     *         1. Hop fee rates updated for all specified tokens
     *         2. TokenFeeSet event emitted for each token
     *
     * @param  tokens     Array of token addresses to configure.
     * @param  hopFeesBPS Array of hop fees in basis points for each corresponding token.
     */
    function setTokenFees(address[] calldata tokens, uint16[] calldata hopFeesBPS) external;

    /**
     * @notice Collects accumulated protocol fees for specified tokens.
     *
     * @dev    Throws when token transfer fails.
     *
     *         Transfers all accumulated protocol fees to the designated fee receiver role holder.
     *         Fees are cleared from storage after successful transfer to prevent double collection.
     *         Function is unrestricted as fees always go to the designated role holder regardless
     *         of caller identity, enabling automated collection systems.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fees transferred to fee receiver
     *         2. Fee balances cleared in storage
     *         3. ProtocolFeesCollected event emitted for each token
     *
     * @param  tokens Array of token addresses to collect protocol fees for.
     */
    function collectProtocolFees(address[] calldata tokens) external;

    /**
     * @notice  Called internally by Limit Break AMM after a swap is finalized to distribute
     *          queued hook fee transfers.
     */
    function executeQueuedHookFeesByHookTransfers() external;
    
    /**
     * @notice  Checks the AMM's execution state using reentrancy flags defined in Constants.sol.
     * 
     * @dev     Flag definitions allow varying granularity of checks from high level of 
     *          "AMM is executing an operation" to detailed "AMM is executing a single pool swap".
     */
    function checkAMMExecutionState(uint256 flags) external view returns (bool);
}
