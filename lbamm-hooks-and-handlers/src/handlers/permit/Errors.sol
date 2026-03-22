//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/// @dev Throws when the caller is not the authorized AMM contract
error PermitTransferHandler__CallbackMustBeFromAMM();

/// @dev Throws when a permit's cosignature has expired.
error PermitTransferHandler__CosignatureExpired();

/// @dev Throws when a permit is being executed with a cosigner that has been destroyed.
error PermitTransferHandler__CosignerDestroyed();

/// @dev Throws when a cosignature nonce has been previously consumed.
error PermitTransferHandler__CosignatureNonceAlreadyConsumed();

/// @dev Throws when a fill or kill permit is executed without filling the full amount.
error PermitTransferHandler__FillOrKillPermitOrderNotFilled();

/// @dev Throws when a permit transfer is called without encoded permit data
error PermitTransferHandler__InvalidDataLength();

/// @dev Throws when a permit transfer is executed with an unrecognized permit type identifier
error PermitTransferHandler__InvalidPermitType();

/// @dev Throws when a partial fill permit exceeds the maximum allowed input for the given output ratio
error PermitTransferHandler__PartialFillExceedsMaximumInputForOutput();

/// @dev Throws when the input/output mode mismatches between permit and swap parameters
error PermitTransferHandler__PermitSwapInputOutputModeMismatch();

/// @dev Throws when a permit transfer fails during execution
error PermitTransferHandler__PermitTransferFailed();