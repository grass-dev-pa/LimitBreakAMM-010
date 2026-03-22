//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMTokenSettings
 * @author Limit Break, Inc.
 * @notice Interface definition for AMM core token setting management and view functions.
 */
interface ILimitBreakAMMTokenSettings {
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
    function setTokenSettings(address token, address tokenHook, uint32 packedSettings) external;

    /**
     * @notice Returns the hook settings and configuration for a specific token.
     *
     * @param  token         The token address to check.
     * @return tokenSettings The complete token settings including hop fee, token configuration and token hook address.
     */
    function getTokenSettings(address token) external view returns (TokenSettings memory tokenSettings);
}
