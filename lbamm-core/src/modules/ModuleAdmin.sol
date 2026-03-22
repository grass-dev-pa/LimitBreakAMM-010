//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./AMMModule.sol";
import "@limitbreak/tm-core-lib/src/utils/access/LibOwnership.sol";
import "@limitbreak/tm-core-lib/src/utils/security/RoleSetClient.sol";

import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  ModuleAdmin
 * @author Limit Break, Inc.
 * @notice Administrative module providing protocol fee management and token configuration.
 *
 * @dev    This contract extends AMMModule with administrative functions for protocol governance.
 *         Uses role-based access control to restrict fee management and collection operations.
 *         Supports protocol fee structure configuration, token-specific hop fees, flash loan fees,
 *         and token settings management.
 *
 * @dev    **Key Features:**
 *         - Protocol fee structure management (LP, exchange, fee-on-top)
 *         - Token-specific hop fee configuration
 *         - Flash loan fee rate control
 *         - Protocol fee collection mechanism
 *         - Token settings and hook configuration
 *         - Role-based access control for administrative operations
 */
contract ModuleAdmin is AMMModule, RoleSetClient {

    /// @dev Role identifier for addresses authorized to modify protocol fee structures and rates.
    bytes32 private immutable LBAMM_FEE_MANAGER_ROLE;

    /// @dev Role identifier for addresses authorized to receive protocol fees.
    bytes32 private immutable LBAMM_FEE_RECEIVER_ROLE;

    constructor(
        address wrappedNative_,
        address roleServer_,
        bytes32 roleSet_
    ) RoleSetClient(roleServer_, roleSet_) AMMModule(wrappedNative_) {
        LBAMM_FEE_MANAGER_ROLE = _hashRoleSetRole(roleSet_, LBAMM_FEE_MANAGER_BASE_ROLE);
        LBAMM_FEE_RECEIVER_ROLE = _hashRoleSetRole(roleSet_, LBAMM_FEE_RECEIVER_BASE_ROLE);
    }

    /**
     * @notice Sets the protocol fee structure for swap and liquidity operations.
     *
     * @dev    Throws when LP fee BPS exceeds maximum allowed.
     *         Throws when exchange fee BPS exceeds maximum allowed.
     *         Throws when fee on top BPS exceeds maximum allowed.
     *         Throws when caller lacks FEE_MANAGER role.
     *
     *         Protocol fees are collected from various operations and distributed according to the
     *         specified structure. LP fees are taken from pool swap fees, while exchange fees and
     *         fees-on-top are applied to individual transactions.
     *
     *         <h4>Postconditions:</h4>
     *         1. Protocol fee structure updated in storage
     *         2. ProtocolFeesSet event emitted with new fee structure
     *
     * @param protocolFeeStructure The structure containing the protocol fees.
     *                               - lpFeeBPS: The BPS fee collected from the LP fee.
     *                               - exchangeFeeBPS: The BPS fee collected for each swap.
     *                               - feeOnTopBPS: The BPS fee collected on top of the exchange fee.
     */
    function setProtocolFees(ProtocolFeeStructure memory protocolFeeStructure)
        external
        callerHasRole(LBAMM_FEE_MANAGER_ROLE)
    {
        _setProtocolFees(protocolFeeStructure);
    }

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
    function setExchangeProtocolFeeOverride(address recipient, bool feeOverrideEnabled, uint256 protocolFeeBPS)
        external
        callerHasRole(LBAMM_FEE_MANAGER_ROLE)
    {
        if (protocolFeeBPS > MAX_BPS) {
            revert LBAMM__FeeAmountExceedsMaxFee();
        }
        ProtocolFeeOverride storage ptrFeeOverride = Storage.appStorage().exchangeProtocolFeeOverride[recipient];
        ptrFeeOverride.feeOverrideEnabled = feeOverrideEnabled;
        ptrFeeOverride.protocolFeeBPS = uint16(protocolFeeBPS);

        emit ExchangeProtocolFeeOverrideSet(recipient, feeOverrideEnabled, uint16(protocolFeeBPS));
    }

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
    function setFeeOnTopProtocolFeeOverride(address recipient, bool feeOverrideEnabled, uint256 protocolFeeBPS)
        external
        callerHasRole(LBAMM_FEE_MANAGER_ROLE)
    {
        if (protocolFeeBPS > MAX_BPS) {
            revert LBAMM__FeeAmountExceedsMaxFee();
        }
        ProtocolFeeOverride storage ptrFeeOverride = Storage.appStorage().feeOnTopProtocolFeeOverride[recipient];
        ptrFeeOverride.feeOverrideEnabled = feeOverrideEnabled;
        ptrFeeOverride.protocolFeeBPS = uint16(protocolFeeBPS);

        emit FeeOnTopProtocolFeeOverrideSet(recipient, feeOverrideEnabled, uint16(protocolFeeBPS));
    }

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
    function setLPProtocolFeeOverride(bytes32 poolId, bool feeOverrideEnabled, uint256 protocolFeeBPS)
        external
        callerHasRole(LBAMM_FEE_MANAGER_ROLE)
    {
        if (protocolFeeBPS > MAX_BPS) {
            revert LBAMM__FeeAmountExceedsMaxFee();
        }
        ProtocolFeeOverride storage ptrFeeOverride = Storage.appStorage().lpProtocolFeeOverride[poolId];
        ptrFeeOverride.feeOverrideEnabled = feeOverrideEnabled;
        ptrFeeOverride.protocolFeeBPS = uint16(protocolFeeBPS);

        emit LPProtocolFeeOverrideSet(poolId, feeOverrideEnabled, uint16(protocolFeeBPS));
    }

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
    function setTokenFees(address[] calldata tokens, uint16[] calldata hopFeesBPS)
        external
        nonReentrant
        callerHasRole(LBAMM_FEE_MANAGER_ROLE)
    {
        if (tokens.length != hopFeesBPS.length) {
            revert LBAMM__ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < tokens.length; ++i) {
            _setTokenFee(tokens[i], hopFeesBPS[i]);
        }
    }
    
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
    function setFlashloanFee(uint256 flashLoanBPS) external callerHasRole(LBAMM_FEE_MANAGER_ROLE) {
        if (flashLoanBPS > type(uint16).max) {
            revert LBAMM__InvalidFlashloanBPS();
        }
        Storage.appStorage().flashLoanBPS = uint16(flashLoanBPS);

        emit FlashloanFeeSet(uint16(flashLoanBPS));
    }

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
    function collectProtocolFees(address[] calldata tokens) external nonReentrant {
        address protocolFeeReceiver = _getRoleHolder(LBAMM_FEE_RECEIVER_ROLE);
        address token;
        uint256 amount;

        for (uint256 i = 0; i < tokens.length; ++i) {
            token = tokens[i];
            amount = Storage.appStorage().protocolFees[token];

            if (amount == 0) {
                continue;
            }

            Storage.appStorage().protocolFees[token] = 0;

            bool isError = SafeERC20.safeTransfer(token, protocolFeeReceiver, amount);
            if (isError) {
                revert LBAMM__ProtocolFeeTransferFailed();
            }
            emit ProtocolFeesCollected(protocolFeeReceiver, token, amount);
        }
    }

    /**
     * @notice Configures token settings including hook integration and operational flags.
     *
     * @dev    Throws when caller is not token owner, contract owner, or admin.
     *         Throws when hook flags are missing required flags.
     *         Throws when hook flags include unsupported flags.
     *
     *         Updates token configuration with hook contract address and packed settings flags.
     *         Validates hook flag compatibility against hook contract requirements and capabilities.
     *         Only authorized parties can modify token settings for security.
     *
     *         <h4>Postconditions:</h4>
     *         1. Token settings updated in storage with new hook and flags
     *         2. Hook flag validation completed against required and supported flags
     *         3. TokenSettingsUpdated event emitted with configuration details
     *
     * @param  token          Token address to configure settings for.
     * @param  tokenHook      Hook contract address for token operations.
     * @param  packedSettings Bit-packed configuration flags for token behavior.
     */
    function setTokenSettings(address token, address tokenHook, uint32 packedSettings) external nonReentrant {
        LibOwnership.requireCallerIsTokenOrContractOwnerOrAdminOrRole(token, LBAMM_TOKEN_SETTING_MANAGER_ROLE);

        if (tokenHook == address(0)) {
            // If hook is being set to zero address, ensure no hook flags are set in packedSettings.
            if (packedSettings != 0) {
                revert LBAMM__UnsupportedHookFlags();
            }
        } else {
            // If a hook is specified, validate that the hook supports the specified flags and 
            // packedSettings includes all required flags for the hook.
            (uint32 requiredFlags, uint32 supportedFlags) = ILimitBreakAMMTokenHook(tokenHook).hookFlags();

            {
                uint32 hookFlags = packedSettings & TOKEN_SETTINGS_HOOK_FLAGS_MASK;
                if (hookFlags & requiredFlags != requiredFlags) revert LBAMM__HookFlagsMissingRequiredFlags();
                if (hookFlags & ~supportedFlags > 0) revert LBAMM__UnsupportedHookFlags();
            }
        }

        TokenSettings storage tokenSettings = Storage.appStorage().tokenSettings[token];
        tokenSettings.packedSettings = packedSettings;
        tokenSettings.tokenHook = tokenHook;

        emit TokenSettingsUpdated(token, tokenHook, packedSettings);
    }

    ///////////////////////////////////////////////////////
    //                   VIEW FUNCTIONS                  //
    ///////////////////////////////////////////////////////

    /**
     * @notice Returns the amount of protocol fees accumulated for a specific token.
     *
     * @param  token The token address to check.
     * @return fees  The amount of accumulated protocol fees.
     */
    function getProtocolFees(address token) external view returns (uint256 fees) {
        fees = Storage.appStorage().protocolFees[token];
    }

    /**
     * @notice Returns the hook settings and configuration for a specific token.
     *
     * @param  token         The token address to check.
     * @return tokenSettings The complete token settings including hop fee, token configuration and token hook address.
     */
    function getTokenSettings(address token) external view returns (TokenSettings memory tokenSettings) {
        tokenSettings = Storage.appStorage().tokenSettings[token];
    }

    /**
     * @notice  Checks the AMM's execution state using reentrancy flags defined in Constants.sol.
     * 
     * @dev     Flag definitions allow varying granularity of checks from high level of 
     *          "AMM is executing an operation" to detailed "AMM is executing a single pool swap".
     */
    function checkAMMExecutionState(uint256 flags) external view returns (bool) {
        return _isReentrancyFlagSet(flags);
    }

    /**
     * @dev Sets up fee manager and fee receiver roles for the contract.
     *
     *      Overrides the virtual function from RoleSetClient to configure contract-specific roles.
     *      Establishes LBAMM_FEE_MANAGER_ROLE and LBAMM_FEE_RECEIVER_ROLE with appropriate permissions.
     *
     *      <h4>Postconditions:</h4>
     *      1. LBAMM_FEE_MANAGER_ROLE configured for fee management operations
     *      2. LBAMM_FEE_RECEIVER_ROLE configured for fee collection operations
     *
     * @param roleSet The role set identifier to derive specific roles from.
     */
    function _setupRoles(bytes32 roleSet) internal virtual override {
        _setupRole(_hashRoleSetRole(roleSet, LBAMM_FEE_MANAGER_BASE_ROLE), 0);
        _setupRole(_hashRoleSetRole(roleSet, LBAMM_FEE_RECEIVER_BASE_ROLE), 0);
    }
}
