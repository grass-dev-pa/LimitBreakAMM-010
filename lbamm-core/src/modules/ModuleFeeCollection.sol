//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./AMMModule.sol";
import "@limitbreak/tm-core-lib/src/utils/access/LibOwnership.sol";

import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  ModuleFeeCollection
 * @author Limit Break, Inc.
 * @notice Fee collection module providing interfaces for retrieving accumulated fees and owed tokens.
 *
 * @dev    This module extends AMMModule with specialized collection functions for different fee types
 *         and debt resolution. Supports hook fee collection with dual management models (hook-managed
 *         vs token-managed) and general token debt collection for failed transfers.
 *
 * @dev    **Key Features:**
 *         - General token debt collection for any address
 *         - Hook fee collection with caller validation
 *         - Token admin fee collection with ownership verification
 *         - Support for both hook-managed and token-managed fee models
 *         - Failed transfer debt resolution mechanism
 */
contract ModuleFeeCollection is AMMModule {
    constructor(
        address wrappedNative_
    ) AMMModule(wrappedNative_) {}

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
    function collectTokensOwed(address[] calldata tokensOwed) external nonReentrant {
        for (uint256 i = 0; i < tokensOwed.length; ++i) {
            _transferTokensOwed(msg.sender, tokensOwed[i]);
        }
    }

    /**
     * @notice Allows hook contracts to collect their accumulated fees.
     *
     * @dev    Throws when caller is not the specified hook contract.
     *         Throws when requested amount exceeds available fees.
     *
     *         Used when token settings specify that hooks manage their own fees. Only the hook
     *         contract itself can call this function to collect its accumulated fees.
     *         If called during a swap, the transfer is queued to be executed at the end of the swap.
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
    function collectHookFeesByHook(address tokenFor, address tokenFee, address recipient, uint256 amount)
        external
    {
        if (_isReentrancyFlagSet(SWAP_GUARD_FLAG) || _isReentrancyFlagSet(LIQUIDITY_GUARD_FLAG)) {
            _queueTransferHookFeesByHook(msg.sender, tokenFor, tokenFee, recipient, amount);
        } else if (_isReentrancyFlagSet(FLASHLOAN_GUARD_FLAG)) {
            revert LBAMM__CannotCollectFeesDuringFlashloan();
        } else {
            _transferHookFeesByHook(msg.sender, tokenFor, tokenFee, recipient, amount);
        }
    }

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
    function collectHookFeesByToken(address tokenFor, address tokenFee, address recipient, uint256 amount)
        external
        nonReentrant
    {
        LibOwnership.requireCallerIsTokenOrContractOwnerOrAdminOrRole(tokenFor, LBAMM_TOKEN_FEE_COLLECTOR_ROLE);
        _transferHookFeesByToken(tokenFor, tokenFee, recipient, amount);
    }

    ///////////////////////////////////////////////////////
    //                 INTERNAL ROUTING                  //
    ///////////////////////////////////////////////////////
    
    /**
     * @notice Executes any queued hook fee transfers that were deferred during swaps.
     *
     * @dev    Throws when a queued transfer fails.
     * @dev    Throws when the queued value is greater than the available fee balance.
     *
     *         This function processes all hook fee transfers that were queued while swaps were
     *         in progress. It is used a self call within the `_finalizeSwapCollectFundsAndDisburse` function.
     *
     *         <h4>Postconditions:</h4>
     *         1. All queued hook fee transfers executed
     */
    function executeQueuedHookFeesByHookTransfers() external {
        if (msg.sender != address(this)) {
            revert LBAMM__CallerMustBeSelf();
        }

        _executeQueuedHookFeesByHookTransfers();
    }

    ///////////////////////////////////////////////////////
    //                   VIEW FUNCTIONS                  //
    ///////////////////////////////////////////////////////

    /**
     * @notice Returns the current flash loan fee rate.
     *
     * @return flashLoanBPS The flash loan fee rate in basis points.
     */
    function getFlashloanFeeBPS() external view returns (uint16 flashLoanBPS) {
        flashLoanBPS = Storage.appStorage().flashLoanBPS;
    }

    /**
     * @notice Returns the amount of tokens owed to a specific user.
     *
     * @param  user               The user's address.
     * @param  token              The token address.
     * @return tokensOwedAmount   The amount of tokens owed to the user.
     */
    function getTokensOwed(address user, address token) external view returns (uint256 tokensOwedAmount) {
        bytes32 tokensOwedKey = EfficientHash.efficientHash(
            LIQUIDITY_OWED,
            EfficientHash.efficientHash(bytes32(uint256(uint160(user))), bytes32(uint256(uint160(token))))
        );
        tokensOwedAmount = Storage.appStorage().tokensOwed[tokensOwedKey];
    }

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
    ) external view returns (uint256 hookFeesOwedAmount) {
        bytes32 hookFeeKey = EfficientHash.efficientHash(
            bytes32(uint256(uint160(hook))),
            EfficientHash.efficientHash(bytes32(uint256(uint160(tokenFor))), bytes32(uint256(uint160(tokenFee))))
        );
        hookFeesOwedAmount = Storage.appStorage().tokensOwed[hookFeeKey];
    }

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
    ) external view returns (uint256 hookFeesOwedAmount) {
        bytes32 hookFeeKey = EfficientHash.efficientHash(
            TOKEN_MANAGED_HOOK_FEE,
            EfficientHash.efficientHash(bytes32(uint256(uint160(tokenFor))), bytes32(uint256(uint160(tokenFee))))
        );
        hookFeesOwedAmount = Storage.appStorage().tokensOwed[hookFeeKey];
    }

    /**
     * @notice Returns the current protocol fee structure.
     *
     * @return protocolFeeDetails The complete protocol fee configuration including lp fee, protocol fee and flat fee on top.
     */
    function getProtocolFeeStructure(
        address exchangeFeeRecipient,
        address feeOnTopFeeRecipient,
        bytes32 poolId
    ) external view returns (ProtocolFeeStructure memory protocolFeeDetails) {
        protocolFeeDetails = Storage.appStorage().protocolFeeStructure;
        ProtocolFeeOverride memory feeOverride = Storage.appStorage().exchangeProtocolFeeOverride[exchangeFeeRecipient];
        if (feeOverride.feeOverrideEnabled) {
            protocolFeeDetails.exchangeFeeBPS = feeOverride.protocolFeeBPS;
        }
        feeOverride = Storage.appStorage().feeOnTopProtocolFeeOverride[feeOnTopFeeRecipient];
        if (feeOverride.feeOverrideEnabled) {
            protocolFeeDetails.feeOnTopBPS = feeOverride.protocolFeeBPS;
        }
        feeOverride = Storage.appStorage().lpProtocolFeeOverride[poolId];
        if (feeOverride.feeOverrideEnabled) {
            protocolFeeDetails.lpFeeBPS = feeOverride.protocolFeeBPS;
        }
    }
}
