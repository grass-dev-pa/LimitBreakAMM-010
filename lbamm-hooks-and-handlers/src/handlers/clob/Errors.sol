//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/// @dev Throws when the caller is not the authorized AMM contract.
error CLOBTransferHandler__CallbackMustBeFromAMM();

/// @dev Throws when attempting to open an order where the input and output tokens are the same.
error CLOBTransferHandler__CannotPairIdenticalTokens();

/// @dev Throws when the fill output exceeds the maximum slippage allowed.
error CLOBTransferHandler__FillOutputExceedsMaxSlippage();

/// @dev Throws when creating a group key that has a zero minimum order size.
error CLOBTransferHandler__GroupMinimumCannotBeZero();

/// @dev Throws when the transfer handler is not the recipient of a swap order.
error CLOBTransferHandler__HandlerMustBeRecipient();

/// @dev Throws when there is insufficient input to fill an order.
error CLOBTransferHandler__InsufficientInputToFill();

/// @dev Throws when the maker's balance is insufficient for a withdrawal or order placement.
error CLOBTransferHandler__InsufficientMakerBalance();

/// @dev Throws when there is insufficient order to fill.
error CLOBTransferHandler__InsufficientOutputToFill();

/// @dev Throws when a clob transfer is called without encoded data.
error CLOBTransferHandler__InvalidDataLength();

/// @dev Throws when the maker of an order does not match the expected maker.
error CLOBTransferHandler__InvalidMaker();

/// @dev Throws when the sender of native value is not the wrapped native contract.
error CLOBTransferHandler__InvalidNativeTransfer();

/// @dev Throws when the current price is invalid.
error CLOBTransferHandler__InvalidPrice();

/// @dev Throws when the sqrt price is below the minimum or above the maximum.
error CLOBTransferHandler__InvalidSqrtPriceX96();

/// @dev Throws when the transfer amount is invalid.
error CLOBTransferHandler__InvalidTransferAmount();

/// @dev Throws when initializing an order book key and the minimum order scale exceeds the maximum value.
error CLOBTransferHandler__MinimumOrderScaleExceedsMaximum();

/// @dev Throws when the order amount exceeds the maximum allowed.
error CLOBTransferHandler__OrderAmountExceedsMax();

/// @dev Throws when an order is placed for an amount less than the CLOB group's minimum.
error CLOBTransferHandler__OrderAmountLessThanGroupMinimum();

/// @dev Throws when closing an order and the order was already closed or is invalid.
error CLOBTransferHandler__OrderInvalidFilledOrClosed();

/// @dev Throws when a swap order is executed as output-based.
error CLOBTransferHandler__OutputBasedNotAllowed();

/// @dev Throws when a CLOB transfer fails during execution.
error CLOBTransferHandler__TransferFailed();

/// @dev Throws when attempting to deposit to the CLOB with a zero amount.
error CLOBTransferHandler__ZeroDepositAmount();

/// @dev Throws when attempting to open a CLOB order with a zero order amount.
error CLOBTransferHandler__ZeroOrderAmount();

/// @dev Throws when attempting to withdraw from the CLOB with a zero amount.
error CLOBTransferHandler__ZeroWithdrawAmount();
