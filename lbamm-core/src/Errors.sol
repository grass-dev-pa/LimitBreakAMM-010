//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/// @dev throws when a pool type returns an actual input/output that exceeds the initial input/output.
error LBAMM__ActualAmountCannotExceedInitialAmount();

/// @dev throws when the array lengths do not match.
error LBAMM__ArrayLengthMismatch();

/// @dev throws when adjusting bytes length for memory allocation and the length exceeds 2^32-1.
error LBAMM__BytesLengthExceedsMax();

/// @dev throws when a caller other than the AMM makes a call to a self only function.
error LBAMM__CallerMustBeSelf();

/// @dev throws when a hook attempts to collect fees during a flashloan operation.
error LBAMM__CannotCollectFeesDuringFlashloan();

/// @dev throws when creating a pool with two identical tokens (same address) is attempted.
error LBAMM__CannotPairIdenticalTokens();

/// @dev throws when a hop execution partially fills after the first hop. 
error LBAMM__CannotPartialFillAfterFirstHop();

/// @dev throws the deadline has passed.
error LBAMM__DeadlineExpired();

/// @dev throws when hook fees on liquidity change exceed the maximum amounts.
error LBAMM__ExcessiveHookFees();

/// @dev throws when the liquidity change exceeds the maximum amounts.
error LBAMM__ExcessiveLiquidityChange();

/// @dev throws when the exchange fee transfer fails.
error LBAMM__ExchangeFeeTransferFailed();

/// @dev throws when the fee amount exceed the input amount of the swap.
error LBAMM__FeeAmountExceedsInputAmount();

/// @dev throws when the fee amount exceeds the maximum fee BPS.
error LBAMM__FeeAmountExceedsMaxFee();

/// @dev throws when the fee on top fails to transfer.
error LBAMM__FeeOnTopTransferFailed();

/// @dev throws when the fee recipient is set to address(0) and a fee amount is set to be transferred.
error LBAMM__FeeRecipientCannotBeAddressZero();

/// @dev throws when a flashloan token hook requests fees in a token that does not allow them.
error LBAMM__FeeTokenNotAllowedForFlashloan();

/// @dev throws when a flashloan callback does not return the proper value.
error LBAMM__FlashloanExecutionFailed();

/// @dev throws when a flashloan token hook requests fees in the zero address token.
error LBAMM__FlashloanFeeTokenCannotBeAddressZero();

/// @dev throws when flash loans are disabled (fee BPS > MAX_FEE).
error LBAMM__FlashloansDisabled();

/// @dev throws when hook flags are missing required flags.
error LBAMM__HookFlagsMissingRequiredFlags();

/// @dev throws when the input token is not wrapped native.
error LBAMM__InputNotWrappedNative();

/// @dev throws when there is not sufficient input amount for the required fees.
error LBAMM__InsufficientInputForFees();

/// @dev throws when the liquidity change does not meet the minimum amounts.
error LBAMM__InsufficientLiquidityChange();

/// @dev throws when there is not sufficient output amount for the required fees.
error LBAMM__InsufficientOutputForFees();

/// @dev throws when a pool type returns an invalid protocol fee.
error LBAMM__InsufficientProtocolFee();

/// @dev throws when insufficient value is provided.
error LBAMM__InsufficientValue();

/// @dev throws when the extra data array is of incorrect length.
error LBAMM__InvalidExtraDataArrayLength();

/// @dev throws when the flash loan bps is set greater than uint16 maximum value.
error LBAMM__InvalidFlashloanBPS();

/// @dev throws when the pool fee is greater than MAX_BPS.
error LBAMM__InvalidPoolFeeBPS();

/// @dev throws when the pool fee hook is not valid.
error LBAMM__InvalidPoolFeeHook();

/// @dev throws when the poolId is not valid.
error LBAMM__InvalidPoolId();

/// @dev throws when the pool type is not valid.
error LBAMM__InvalidPoolType();

/// @dev throws when transfer handler calldata is supplied but the first 32 bytes is not an address.
error LBAMM__InvalidTransferHandler();

/// @dev throws when an limit provided is exceeded.
error LBAMM__LimitAmountExceeded();

/// @dev throws when the limit amount is not met.
error LBAMM__LimitAmountNotMet();

/// @dev throws when the liquidity data provided during pool creation does not direct to the addLiquidity function.
error LBAMM__LiquidityDataDoesNotCallAddLiquidity();

/// @dev throws when a multi hop swap does not contain any hops.
error LBAMM__NoPoolsProvidedForMultiswap();

/// @dev throws when an overflow occurs.
error LBAMM__Overflow();

/// @dev throws when a partial fill on an output swap is less than the fees required by hooks.
error LBAMM__PartialFillLessThanFees();

/// @dev throws when a partial fill's actual amount filled is less than the minimum amount specified on the swap order.
error LBAMM__PartialFillLessThanMinimumSpecified();

/// @dev throws when a pool already exists.
error LBAMM__PoolAlreadyExists();

/// @dev throws when a pool is created with add liquidity data and there is no liquidity added.
error LBAMM__PoolCreationWithLiquidityDidNotAddLiquidity();

/// @dev throws when a pool is being created and one of the paired tokens has no code.
error LBAMM__PoolCreationWithNoCodeAtToken();

/// @dev throws when a pool does not exist.
error LBAMM__PoolDoesNotExist();

/// @dev throws when setting a pool fee greater than MAX_BPS is attempted.
error LBAMM__PoolFeeMustBeLessThan100Percent();

/// @dev throws when pool hook data is provided but not supported.
error LBAMM__PoolHookDataNotSupported();

/// @dev throws when the transfer of the protocol fee fails.
error LBAMM__ProtocolFeeTransferFailed();

/// @dev throws when the swapOrder recipient is address(0).
error LBAMM__RecipientCannotBeAddressZero();

/// @dev throws when a refund transfer fails.
error LBAMM__RefundFailed();

/// @dev throws when the transfer of tokenIn fails.
error LBAMM__TokenInTransferFailed();

/// @dev throws when the transfer of tokenOut fails.
error LBAMM__TokenOutTransferFailed();

/// @dev throws when the transfer of the token owed to a user fails.
error LBAMM__TokenOwedTransferFailed();

/// @dev throws when the transfer of the hook fee fails.
error LBAMM__TransferHookFeeTransferFailed();

/// @dev throws when an underflow occurs.
error LBAMM__Underflow();

/// @dev throws when an unsupported hook flag is set.
error LBAMM__UnsupportedHookFlags();

/// @dev throws when the provided value is not used.
error LBAMM__ValueNotUsed();
