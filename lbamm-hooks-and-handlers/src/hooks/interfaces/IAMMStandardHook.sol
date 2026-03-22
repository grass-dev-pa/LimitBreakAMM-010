//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../DataTypes.sol";
import "@limitbreak/lb-amm-core/src/interfaces/hooks/ILimitBreakAMMTokenHook.sol";

/**
 * @title  IAMMStandardHook
 * @author Limit Break, Inc.
 * @notice Interface definition for the AMM Standard Hook.
 */
interface IAMMStandardHook is ILimitBreakAMMTokenHook {
    /// @dev Emitted when a liquidity provider address is added to a whitelist.
    event LpAddressAddedtoWhitelist(
        uint256 indexed lpWhitelistId,
        address indexed lpAddress
    );

    /// @dev Emitted when a liquidity provider address is removed from a whitelist.
    event LpAddressRemovedFromWhitelist(
        uint256 indexed lpWhitelistId,
        address indexed lpAddress
    );

    /// @dev Emitted when a pair token is added to a whitelist.
    event PairTokenAddedToWhitelist(
        uint256 indexed pairTokenWhitelistId,
        address indexed pairToken
    );

    /// @dev Emitted when a pair token is removed from a whitelist.
    event PairTokenRemovedFromWhitelist(
        uint256 indexed pairTokenWhitelistId,
        address indexed pairToken
    );

    /// @dev Emitted when a pool type is added to a whitelist.
    event PoolTypeAddedToWhitelist(
        uint256 indexed poolTypeWhitelistId,
        address indexed poolType
    );

    /// @dev Emitted when a pool type is removed from a whitelist.
    event PoolTypeRemovedFromWhitelist(
        uint256 indexed poolTypeWhitelistId,
        address indexed poolType
    );

    /// @dev Emitted when pricing bounds for a pair of tokens is updated.
    event PricingBoundsSet(
        address indexed token,
        address indexed pairToken,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96
    );

    /// @dev Emitted when pricing bounds for a pair of tokens is unset.
    event PricingBoundsUnset(
        address indexed token,
        address indexed pairToken
    );

    /// @dev Emitted when a token updates its hook settings.
    event TokenSettingsUpdated(
        address indexed token,
        HookTokenSettings tokenSettings
    );

    /**
     * @notice Updates the local cache for a pair token whitelist based on data from the registry.
     *
     * @dev    Throws if caller is not the registry or this contract.
     *
     * @dev    Only callable by the trusted registry contract or this contract itself. Adds or removes
     *         addresses from the specified pair token whitelist and emits events for each change.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Addresses have been added to or removed from `_pairTokenWhitelists[pairTokenWhitelistId]`.
     * @dev    2. `PairTokenAddedToWhitelist` events have been emitted for each successfully added address.
     * @dev    3. `PairTokenRemovedFromWhitelist` events have been emitted for each successfully removed address.
     *
     * @param  pairTokenWhitelistId  The ID of the whitelist to update.
     * @param  pairTokens            Array of token addresses to add or remove from the whitelist.
     * @param  pairTokensAdded       True to add addresses to the whitelist, false to remove them.
     */
    function registryUpdateWhitelistPairToken(
        uint256 pairTokenWhitelistId,
        address[] calldata pairTokens,
        bool pairTokensAdded
    ) external;

    /**
     * @notice Updates the local cache for an LP whitelist based on data from the registry.
     *
     * @dev    Throws if caller is not the registry or this contract.
     *
     * @dev    Only callable by the trusted registry contract or this contract itself. Adds or removes
     *         addresses from the specified LP whitelist and emits events for each change.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Addresses have been added to or removed from `_lpWhitelists[lpWhitelistId]`.
     * @dev    2. `LpAddressAddedtoWhitelist` events have been emitted for each successfully added address.
     * @dev    3. `LpAddressRemovedFromWhitelist` events have been emitted for each successfully removed address.
     *
     * @param  lpWhitelistId     The ID of the LP whitelist to update.
     * @param  lpAddresses       Array of addresses to add or remove from the whitelist.
     * @param  lpAddressesAdded  True to add addresses to the whitelist, false to remove them.
     */
    function registryUpdateWhitelistLpAddress(
        uint256 lpWhitelistId,
        address[] calldata lpAddresses,
        bool lpAddressesAdded
    ) external;

    /**
     * @notice Updates the local cache for a pool type whitelist based on data from the registry.
     *
     * @dev    Throws if caller is not the registry or this contract.
     *
     * @dev    Only callable by the trusted registry contract or this contract itself. Adds or removes
     *         addresses from the specified pool type whitelist and emits events for each change.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Addresses have been added to or removed from `_poolTypeWhitelists[poolTypeWhitelistId]`.
     * @dev    2. `PoolTypeAddedToWhitelist` events have been emitted for each successfully added address.
     * @dev    3. `PoolTypeRemovedFromWhitelist` events have been emitted for each successfully removed address.
     *
     * @param  poolTypeWhitelistId  The ID of the whitelist to update.
     * @param  poolTypes            Array of pool addresses to add or remove from the whitelist.
     * @param  poolTypesAdded       True to add addresses to the whitelist, false to remove them.
     */
    function registryUpdateWhitelistPoolType(
        uint256 poolTypeWhitelistId,
        address[] calldata poolTypes,
        bool poolTypesAdded
    ) external;

    /**
     * @notice Updates the local cache for a specific token's settings based on data from the registry.
     *
     * @dev    Throws if caller is not the registry or this contract.
     *
     * @dev    Only callable by the trusted registry contract or this contract itself. Directly updates
     *         the token settings cache with the provided settings structure.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. `_tokenSettings[token]` cache has been updated with the new settings.
     * @dev    2. `TokenSettingsUpdated` event has been emitted with the token and new settings.
     *
     * @param  token          The address of the token whose settings are being updated.
     * @param  tokenSettings  The new settings structure containing all token configuration parameters.
     */
    function registryUpdateTokenSettings(address token, HookTokenSettings calldata tokenSettings) external;

    /**
     * @notice Updates the local cache for pricing bounds of a specific token against multiple pair tokens.
     *
     * @dev    Throws if caller is not the registry or this contract.
     * @dev    Throws if any max price is less than its corresponding min price.
     *
     * @dev    Only callable by the trusted registry contract or this contract itself. Updates pricing bounds
     *         for the specified token against each provided pair token, validating that max prices are not
     *         lower than min prices.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. `_pricingBounds[token][pairToken]` cache has been updated for each pair token.
     * @dev    2. `PricingBoundsSet` events have been emitted for each pair token with the new bounds.
     *
     * @param  token             The address of the token for which pricing bounds are being set.
     * @param  pairTokens        Array of pair token addresses that will have bounds set against the main token.
     * @param  minSqrtPriceX96   Array of minimum square root prices in X96 format corresponding to each pair token.
     * @param  maxSqrtPriceX96   Array of maximum square root prices in X96 format corresponding to each pair token.
     */
    function registryUpdatePricingBounds(
        address token,
        address[] calldata pairTokens,
        uint160[] calldata minSqrtPriceX96,
        uint160[] calldata maxSqrtPriceX96
    ) external;

    /**
     * @notice Checks if a pair token is whitelisted for a given whitelist ID.
     *
     * @dev    Uses the local cache to check if the provided address is in the specified whitelist. Returns false
     *         if the whitelist doesn't exist or the token is not present.
     *         NOTE: The cache can be out of sync with the registry by design. This function does not
     *         guarantee that the token is whitelisted in the registry.
     *
     * @param  pairTokenWhitelistId   The ID of the whitelist to check against.
     * @param  pairToken              The address of the pair token to verify.
     * @return pairTokenWhitelisted   True if the pair token is in the specified whitelist, false otherwise.
     */
    function isWhitelistedPairToken(
        uint256 pairTokenWhitelistId,
        address pairToken
    ) external view returns (bool pairTokenWhitelisted);

    /**
     * @notice Checks if an address is whitelisted as a liquidity provider for a given whitelist ID.
     *
     * @dev    Uses the local cache to check membership in the specified LP whitelist. Returns false
     *         if the whitelist doesn't exist or the address is not present.
     *         NOTE: The cache can be out of sync with the registry by design. This function does not
     *         guarantee that the address is whitelisted in the registry.
     *
     * @param  lpWhitelistId   The ID of the LP whitelist to check against.
     * @param  account         The address of the potential liquidity provider to verify.
     * @return lpWhitelisted   True if the address is in the specified LP whitelist, false otherwise.
     */
    function isWhitelistedLiquidityProvider(
        uint256 lpWhitelistId,
        address account
    ) external view returns (bool lpWhitelisted);
}