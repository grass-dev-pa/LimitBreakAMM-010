//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMFees
 * @author Limit Break, Inc.
 * @notice Interface definition for AMM core fee collection and view functions.
 */
interface ILimitBreakAMMFees {
    /**
     * @notice Collects tokens owed to the caller from various fee distributions.
     *
     * @dev    Throws when token transfer fails.
     *         Throws when no tokens owed for specified address-token pairs.
     *
     *         Used to collect hook fees, failed transfer amounts, and other owed tokens accumulated
     *         for the caller across different operations.
     *
     *         <h4>Postconditions:</h4>
     *         1. All owed tokens transferred to caller
     *         2. Owed balances cleared in storage
     *         3. TokensClaimed events emitted for successful transfers
     *
     * @param  tokensOwed Array of token addresses to collect owed amounts for.
     */
    function collectTokensOwed(address[] calldata tokensOwed) external;

    /**
     * @notice Allows hook contracts to collect their accumulated fees.
     *
     * @dev    Throws when caller is not the specified hook contract.
     *         Throws when requested amount exceeds available fees.
     *
     *         Used when token settings specify that hooks manage their own fees. Only the hook
     *         contract itself can call this function to collect its accumulated fees.
     *
     *         <h4>Postconditions:</h4>
     *         1. Hook fees transferred to specified recipient
     *         2. Fee balance reduced by collected amount
     *         3. TokensClaimed events emitted for successful transfers
     *
     * @param  tokenFor  The token address the fees are associated with.
     * @param  tokenFee  The token address being collected as fee payment.
     * @param  recipient Address to receive the collected fees.
     * @param  amount    Amount of fees to collect.
     */
    function collectHookFeesByHook(address tokenFor, address tokenFee, address recipient, uint256 amount) external;

    /**
     * @notice Allows token administrators to collect hook fees for their tokens.
     *
     * @dev    Throws when caller lacks admin permissions for the token.
     *         Throws when requested amount exceeds available fees.
     *
     *         Used when token settings specify that tokens manage their own hook fees. Only the
     *         token contract or its admin can collect these fees.
     *
     *         <h4>Postconditions:</h4>
     *         1. Hook fees transferred to specified recipient
     *         2. Fee balance reduced by collected amount
     *         3. TokensClaimed events emitted for successful transfers
     *
     * @param  tokenFor  The token address the fees are associated with.
     * @param  tokenFee  The token address being collected as fee payment.
     * @param  recipient Address to receive the collected fees.
     * @param  amount    Amount of fees to collect.
     */
    function collectHookFeesByToken(address tokenFor, address tokenFee, address recipient, uint256 amount) external;

    /**
     * @notice Returns the amount of tokens owed to a specific user.
     *
     * @param  user               The user's address.
     * @param  token              The token address.
     * @return tokensOwedAmount   The amount of tokens owed to the user.
     */
    function getTokensOwed(address user, address token) external view returns (uint256 tokensOwedAmount);

    /**
     * @notice Returns hook fees owed to a specific hook contract.
     *
     * @param  hook                  The hook contract address.
     * @param  tokenFor              The token the fees are associated with.
     * @param  tokenFee              The token being used for fee payment.
     * @return hookFeesOwedAmount    The amount of hook fees owed.
     */
    function getHookFeesOwedByHook(
        address hook,
        address tokenFor,
        address tokenFee
    ) external view returns (uint256 hookFeesOwedAmount);

    /**
     * @notice Returns hook fees owed for a specific token.
     *
     * @param  tokenFor              The token the fees are associated with.
     * @param  tokenFee              The token being used for fee payment.
     * @return hookFeesOwedAmount    The amount of hook fees owed.
     */
    function getHookFeesOwedByToken(
        address tokenFor,
        address tokenFee
    ) external view returns (uint256 hookFeesOwedAmount);
}
