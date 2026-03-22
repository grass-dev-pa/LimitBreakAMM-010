//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/// @dev throws when an input-based executes as output-based due to reserve constraints and input exceeds the original amount.
error SingleProviderPool__ActualAmountCannotExceedInitialAmount();

/// @dev throws when insufficient reserves are available for a swap or liquidity modification.
error SingleProviderPool__InsufficientReserves();

/// @dev throws when a provided fee rate exceeds the maximum allowed for the operation.
error SingleProviderPool__InvalidFeeBPS();

/// @dev throws when the pool hook provides an out of range price.
error SingleProviderPool__InvalidPrice();

/// @dev throws when no pool hook is provided during pool creation.
error SingleProviderPool__NoPoolHookProvided();

/// @dev throws when an unauthorized provider attempts to modify liquidity.
error SingleProviderPool__NotAllowedProvider();

/// @dev throws when an operation is attempted by someone other than the designated AMM.
error SingleProviderPool__OnlyAMM();