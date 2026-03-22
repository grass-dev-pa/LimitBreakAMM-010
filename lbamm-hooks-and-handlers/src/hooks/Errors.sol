//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/// @dev throws when caller is not the AMM.
error AMMStandardHook__CallerIsNotAMM();

/// @dev throws when caller is not the Hook Settings Registry.
error AMMStandardHook__CallerIsNotRegistry();

/// @dev throws when a direct swap is executed on a token that does not allow direct swaps.
error AMMStandardHook__DirectSwapsNotAllowed();

/// @dev throws when a hook function is called but not implemented by the hook contract.
error AMMStandardHook__HookFunctionNotSupported();

/// @dev throws when the provided creator hook settings registry address is the zero address.
error AMMStandardHook__InvalidAddress();

/// @dev throws when the provided price violates the configured bounds.
error AMMStandardHook__InvalidPrice();

/// @dev throws during liquidity modification when the provider is not authorized.
error AMMStandardHook__LiquidityProviderNotAllowed();

/// @dev throws when modifying price and the max price is less than the min price.
error AMMStandardHook__MaxPriceMustBeGreaterThanOrEqualToMinPrice();

/// @dev throws when the combination of tokens is not allowed.
error AMMStandardHook__PairNotAllowed();

/// @dev throws when the pool is disabled in the hook settings registry.
error AMMStandardHook__PoolDisabled(bytes32 poolId);

/// @dev throws during pool creation when the pool fee is above the maximum threshold.
error AMMStandardHook__PoolFeeTooHigh();

/// @dev throws during pool creation when the pool fee is below the minimum threshold.
error AMMStandardHook__PoolFeeTooLow();

/// @dev throws during pool creation when a pool type is not allowed.
error AMMStandardHook__PoolTypeNotAllowed();

/// @dev throws when a token is being flash loaned but has turned on the flag to disallow usage.
error AMMStandardHook__TokenNotAllowedAsFlashloan();

/// @dev throws when a token is being used as a fee token for a flashloan but has turned on the flag to disallow usage.
error AMMStandardHook__TokenNotAllowedAsFlashloanFee();

/// @dev throws during a hook invocation when a token has not initialized settings in the registry.
error AMMStandardHook__TokenSettingsNotInitialized();

/// @dev throws before swap when trading is paused for a token.
error AMMStandardHook__TradingPaused();

/// @dev throws when the caller does not own the LP Whitelist.
error CreatorHookSettingsRegistry__CallerDoesNotOwnLpWhitelist();

/// @dev throws when the caller does not own the pair token whitelist.
error CreatorHookSettingsRegistry__CallerDoesNotOwnPairTokenWhitelist();

/// @dev throws when the caller does not own the pool type whitelist.
error CreatorHookSettingsRegistry__CallerDoesNotOwnPoolTypeWhitelist();

/// @dev throws when setting token settings and the provided list id has not been created.
error CreatorHookSettingsRegistry__InvalidListId();

/// @dev throws when the proposed owner of a list is address(0).
error CreatorHookSettingsRegistry__InvalidOwner();

/// @dev throws when there is a mismatch in the length of the provided arrays.
error CreatorHookSettingsRegistry__LengthOfProvidedArraysMismatch();

/// @dev throws when the maximum price is below the minimum price.
error CreatorHookSettingsRegistry__MaxPriceMustBeGreaterThanOrEqualToMinPrice();

/// @dev thrown when setting a disabled pool and the specified token is not one of the paired tokens.
error CreatorHookSettingsRegistry__TokenIsNotInPair();