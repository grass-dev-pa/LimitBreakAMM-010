//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../DataTypes.sol";

/**
 * @title  ICreatorHookSettingsRegistry
 * @author Limit Break, Inc.
 * @notice Interface definition for the AMM standard hook settings registry.
 */
interface ICreatorHookSettingsRegistry {
    /// @dev Emitted when bytes expansion data settings are set for a token.
    event ExpansionDatumsSet(address indexed token, bytes32 indexed key, bytes value);

    /// @dev Emitted when bytes32 expansion data settings are set for a token.
    event ExpansionWordsSet(address indexed token, bytes32 indexed key, bytes32 value);
    
    /// @dev Emitted when a liquidity provider whitelist is created.
    event LpWhitelistCreated(uint256 indexed listId, address indexed owner, string name);
    
    /// @dev Emitted when a liquidity provider whitelist's ownership is transferred.
    event LpWhitelistOwnershipTransferred(
        uint256 indexed listId,
        address indexed previousOwner,
        address indexed newOwner
    );

    /// @dev Emitted when a liquidity provider is added to or removed from a whitelist.
    event LpWhitelistUpdated(uint256 indexed listId, address indexed account, bool added);

    /// @dev Emitted when a pair token whitelist is created.
    event PairTokenWhitelistCreated(uint256 indexed listId, address indexed owner, string name);

    /// @dev Emitted when a pair token whitelist's ownership is transferred.
    event PairTokenWhitelistOwnershipTransferred(
        uint256 indexed listId,
        address indexed previousOwner,
        address indexed newOwner
    );

    /// @dev Emitted when a pair token is added to or removed from a whitelist.
    event PairTokenWhitelistUpdated(uint256 indexed listId, address indexed token, bool added);

    /// @dev Emitted when a pool type whitelist is created.
    event PoolTypeWhitelistCreated(uint256 indexed listId, address indexed owner, string name);

    /// @dev Emitted when a pool type whitelist's ownership is transferred.
    event PoolTypeWhitelistOwnershipTransferred(
        uint256 indexed listId,
        address indexed previousOwner,
        address indexed newOwner
    );

    /// @dev Emitted whena  pool type is added to or removed from a whitelist.
    event PoolTypeWhitelistUpdated(
        uint256 indexed listId,
        address indexed poolType,
        bool added
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
    event TokenSettingsSet(address indexed token, HookTokenSettings settings);

    /// @dev Emitted when a pool is disabled by one of the tokens in the pair.
    event PoolDisabled(bytes32 indexed poolId);

    /// @dev Emitted when a disabled pool is reenabled.
    event PoolEnabled(bytes32 indexed poolId);

    /**
     * @notice Retrieves the hook settings for a specific token.
     *
     * @dev    Callers should check the `initialized` flag within the returned struct.
     *
     * @param  token         The token address.
     * @return tokenSettings The HookTokenSettings struct containing comprehensive token configuration including fees, 
     *                       trading controls, whitelists, and operational parameters. See `DataTypes.sol` for field details.
     */
    function getTokenSettings(address token) external view returns (HookTokenSettings memory tokenSettings);

    /**
     * @notice Checks if the specified poolId is disabled.
     *
     * @param  poolId   ID of the pool to check if it is disabled.
     * @return disabled True if the pool is disabled by either token in the pair.
     */
    function isPoolDisabled(bytes32 poolId) external view returns (bool disabled);

    /**
     * @notice Retrieves the pricing bounds for a specific token and pair token.
     *
     * @dev    Callers should check the `isSet` flag within the returned struct to determine if bounds are active.
     * @dev    Returns `isSet` as `false` if the token is not initialized or the price bound is not active.
     *
     * @param  token      The token address.
     * @param  pairToken  The pair token address.
     * @return bounds     The pricing bounds struct containing (bool isSet, uint160 minSqrtPriceX96, uint160 maxSqrtPriceX96).
     */
    function getPriceBounds(address token, address pairToken) external view returns (PricingBounds memory bounds);

    /**
     * @notice Retrieves the extended data for a specific token given an array of keys.
     *
     * @dev    If the `extensions` array is empty, an empty array is returned.
     * @dev    If the `extensions` array contains keys that do not exist in the mapping, those entries will be empty.
     *
     * @param  token       The token address.
     * @param  extensions  An array of `bytes32` keys for the requested extensions.
     * @return data        An array of `bytes` containing the extended data for each key.
     */
    function getTokenExtendedData(
        address token,
        bytes32[] calldata extensions
    ) external view returns (bytes[] memory data);

    /**
     * @notice Retrieves the extended words for a specific token given an array of keys.
     *
     * @dev    If the `extensions` array is empty, an empty array is returned.
     * @dev    If the `extensions` array contains keys that do not exist in the mapping, those entries will be empty.
     *
     * @param  token       The token address.
     * @param  extensions  An array of `bytes32` keys for the requested extensions.
     * @return words       An array of `bytes32` values corresponding to the requested extension keys.
     */
    function getTokenExtendedWords(
        address token,
        bytes32[] calldata extensions
    ) external view returns (bytes32[] memory words);

    /**
     * @notice Checks if settings for a specific token have been initialized in this registry.
     *
     * @dev    Checks the `initialized` flag within the stored `HookTokenSettings` struct.
     *
     * @param  token The token address.
     * @return isInitialized True if settings have been set via `setTokenSettings`, false otherwise.
     */
    function isTokenInitialized(address token) external view returns (bool isInitialized);
    
    /**
     * @notice Sets or updates the hook settings for a specific token.
     *
     * @dev    The `initialized` flag within the stored `settings` struct will always be set to true.
     * @dev    Throws when the caller is not the token contract, owner, or default admin.
     * @dev    Throws when accessing dataSettings[i] or wordSettings[i] goes out of bounds (solidity panic)
     * @dev    Throws when any hook synchronization call fails.
     *
     * @dev    <h4>Hook Synchronization:</h4>
     * @dev    If `hooksToSync` is provided, this function calls `registrySyncTokenSettings` on each hook.
     * @dev    This syncs the `HookTokenSettings` struct (including `pairedTokenWhitelistId` and `lpWhitelistId`)
     * @dev    to the hook. However, it does **not** sync the *actual content* (member addresses) of the referenced
     * @dev    whitelists from this registry to the hook's local cache. Updating a hook's whitelist content cache
     * @dev    is a separate, explicit operation on the hook contract itself.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Settings for `token` updated in `_tokenSettings` mapping with `initialized` set to true.
     * @dev    2. Extension data stored in `_tokenSettingsExtensionData[token]` for each provided key-value pair.
     * @dev    3. Extension words stored in `_tokenSettingsExtensionWords[token]` for each provided key-value pair.
     * @dev    4. `registrySyncTokenSettings` called on each hook in `hooksToSync` array.
     * @dev    5. `TokenSettingsSet` event emitted with the updated settings.
     *
     * @param  token          The token address for which settings are being configured.
     * @param  settings       The hook settings struct.
     * @param  dataExtensions An array of `bytes32` keys for extension data.
     * @param  dataSettings   An array of `bytes` values for extension data.
     * @param  wordExtensions An array of `bytes32` keys for extension words.
     * @param  wordSettings   An array of `bytes32` values for extension words.
     * @param  hooksToSync    An array of hook addresses to sync with the new settings.
     */
    function setTokenSettings(
        address token,
        HookTokenSettings calldata settings,
        bytes32[] memory dataExtensions,
        bytes[] memory dataSettings,
        bytes32[] memory wordExtensions,
        bytes32[] memory wordSettings,
        address[] calldata hooksToSync
    ) external;

    /**
     * @notice Sets the disabled state of a pool.
     *
     * @dev    Either token in the pool may set the pool to disabled with each token's flag being
     * @dev    stored separately. If both tokens set the pool to disabled, both tokens must reenable.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Pool disabled state for `poolId` updated in `_disabledPools` mapping.
     * @dev    2. `PoolDisabled` or `PoolEnabled` event is emitted if the state has changed.
     *
     * @param  token    Address of the pool token the caller has permission for.
     * @param  poolId   The id of the pool to disable or enable.
     * @param  disable  True if the pool should be disabled, false to enable.
     */
    function setPoolDisabled(
        address token,
        bytes32 poolId,
        bool disable
    ) external;

    /**
     * @notice Sets or updates the expansion settings for a specific token.
     *
     * @dev    Throws when the caller is not the token contract, owner, or default admin.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Extension words stored in `_tokenSettingsExtensionWords[token]` for each provided key-value pair.
     * @dev    2. Extension data stored in `_tokenSettingsExtensionData[token]` for each provided key-value pair.
     * @dev    3. `ExpansionWordsSet` event emitted for each expansion word with its key and value.
     * @dev    4. `ExpansionDatumsSet` event emitted for each expansion datum with its key and value.
     *
     * @dev    <h4>Important Considerations:</h4>
     * @dev    The `expansionWords` and `expansionDatums` values are stored as key-value pairs in the extension storage.
     * @dev    The caller should ensure that these values are set correctly to avoid unexpected behavior in the AMM.
     * @dev    This function does not push the changes to the hooks. If you want to use this data in the hooks,
     * @dev    you need to call `getTokenExtendedData` or `getTokenExtendedWords` in the hook contract.
     * 
     * @param  token             The token address for which expansion settings are being set.
     * @param  expansionWords    An array of `ExpansionWord` structs containing the keys and values.
     * @param  expansionDatums   An array of `ExpansionDatum` structs containing the keys and values.
     */
    function setExpansionSettingsOfCollection(
        address token,
        ExpansionWord[] calldata expansionWords,
        ExpansionDatum[] calldata expansionDatums
    ) external;

    /**
     * @notice Sets or updates the pricing bounds for a specific token and its pair tokens.
     *
     * @dev    Throws when the caller is not the token contract, owner, or default admin.
     * @dev    Throws when the lengths of `pairTokens`, `minSqrtPriceX96`, and `maxSqrtPriceX96` arrays do not match.
     * @dev    Throws when any `minSqrtPriceX96` is greater than the corresponding `maxSqrtPriceX96`.
     * @dev    Throws when any hook synchronization call fails.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Pricing bounds for each pair token are set in `_pricingBounds[token]`.
     * @dev    2. `PricingBoundsSet` event emitted for each pair token with its bounds.
     * @dev    3. `registryUpdatePricingBounds` called on each hook in `hooksToSync` array.
     *
     * @dev    <h4>Important Considerations:</h4>
     * @dev    The `minSqrtPriceX96` and `maxSqrtPriceX96` values are expected to be in the format of a square root price.
     * @dev    The caller should ensure that these values are set correctly to avoid unexpected behavior in the AMM.
     * @dev    The function does not perform any checks on the validity of the provided token addresses or their
     * @dev    corresponding pair tokens. It is the caller's responsibility to ensure that the provided addresses
     * @dev    are valid and correspond to the intended tokens. If there are multiple pairing tokens allowed, it
     * @dev    should be known the price bounds will be "fuzzy" as the dollar value of each pairing token will
     * @dev    differ, allowing for arbitrage opportunities.
     *
     * @param  token           The token address for which pricing bounds are being set.
     * @param  pairTokens      An array of pair token addresses.
     * @param  minSqrtPriceX96 An array of minimum square root prices for each pair token.
     * @param  maxSqrtPriceX96 An array of maximum square root prices for each pair token.
     * @param  hooksToSync     An array of addresses for hooks to sync with the new pricing bounds.
     */
    function setPricingBounds(
        address token,
        address[] calldata pairTokens,
        uint160[] calldata minSqrtPriceX96,
        uint160[] calldata maxSqrtPriceX96,
        address[] calldata hooksToSync
    ) external;

    /**
     * @notice Gets the owner of a specific LP Whitelist.
     *
     * @dev    Returns `address(0)` if the `listId` is invalid or ownership has been renounced.
     *
     * @param  listId The ID of the LP Whitelist.
     * @return owner  The address of the current owner.
     */
    function getLpWhitelistOwner(uint256 listId) external view returns (address owner);

    /**
     * @notice Gets all account addresses currently in a specific LP Whitelist.
     *
     * @dev    Returns an empty array if the `listId` is invalid or the list is empty.
     *
     * @param  listId   The ID of the LP Whitelist.
     * @return accounts An array containing all addresses in the specified list.
     */
    function getLpsInList(uint256 listId) external view returns (address[] memory accounts);

    /**
     * @notice Checks if a specific account is present in a given LP Whitelist.
     *
     * @dev    Returns `false` if the `listId` is invalid or the account is not in the list.
     *
     * @param  listId  The ID of the LP Whitelist.
     * @param  account The account address to check.
     * @return isWhitelisted True if the account is in the list, false otherwise.
     */
    function isWhitelistedLp(uint256 listId, address account) external view returns (bool);

    /**
    * @notice Creates a new, empty LP whitelist.
    * 
    * @dev    Callable by anyone. The whitelist ID is auto-generated starting from 1, and the caller
    *         becomes the owner with full control over whitelist membership.
    * 
    * @dev    <h4>Postconditions:</h4>
    * @dev    1. A new whitelist is created with ID `_nextLpListId`.
    * @dev    2. The caller is set as the owner of the new whitelist.
    * @dev    3. The next available list ID counter is incremented.
    * @dev    4. A `LpWhitelistCreated` event is emitted.
    *
    * @param  whitelistName A descriptive name for the whitelist (used in events only).
    * @return listId        The ID of the newly created LP whitelist.
    */
    function createLpWhitelist(string calldata whitelistName) external returns (uint256 listId);

    /**
     * @notice Transfers ownership of the provided LP whitelist to a new owner.
     *
     * @dev    Throws when `newOwner` is the zero address.
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Ownership stored in `_lpWhitelistOwners[listId]` is updated to `newOwner`.
     * @dev    2. A `LpWhitelistOwnershipTransferred` event is emitted.
     *
     * @param  listId   The ID of the LP whitelist to transfer.
     * @param  newOwner The address of the new owner.
     */
    function transferLpWhitelistOwnership(uint256 listId, address newOwner) external;

    /**
     * @notice Adds or removes accounts from a specified LP whitelist.
     *
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     * @dev    Throws when any hook synchronization call fails.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. If adding, account added to `_lpWhitelists[listId]` set if not already present.
     * @dev    2. If removing, account removed from `_lpWhitelists[listId]` set if present.
     * @dev    3. `LpWhitelistUpdated` event emitted for each successful addition or removal.
     * @dev    4. `registryUpdateWhitelistLpAddress` called on each hook in `hooksToSync` array.
     *
     * @dev    <h4>Important Considerations:</h4>
     * @dev    Consider gas limits if the `accounts` array is very large.
     * @dev    Events are only emitted when actual changes occur (successful additions or removals).
     *
     * @param  listId      The ID of the LP whitelist to update.
     * @param  accounts    An array of account addresses to add or remove.
     * @param  add         True to add accounts, false to remove accounts.
     * @param  hooksToSync An array of addresses for hooks to sync with the new whitelist.
     */
    function updateLpWhitelist(
        uint256 listId,
        address[] calldata accounts,
        bool add,
        address[] calldata hooksToSync
    ) external;

    /**
     * @notice Renounces ownership of the provided LP whitelist, making the list immutable.
     *
     * @dev    Transfers ownership to the zero address. List contents can no longer be modified.
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Ownership stored in `_lpWhitelistOwners[listId]` is updated to `address(0)`.
     * @dev    2. A `LpWhitelistOwnershipTransferred` event is emitted with `newOwner` as `address(0)`.
     *
     * @param  listId The ID of the LP whitelist to renounce ownership of.
     */
    function renounceLpWhitelistOwnership(uint256 listId) external;

    /**
     * @notice Gets the owner of a specific Pair Token Whitelist.
     *
     * @dev    Returns `address(0)` if the `listId` is invalid or ownership has been renounced.
     *
     * @param  listId The ID of the Pair Token Whitelist.
     * @return owner  The address of the current owner.
     */
    function getPairTokenWhitelistOwner(uint256 listId) external view returns (address owner);

    /**
     * @notice Gets all token addresses currently in a specific Pair Token Whitelist.
     *
     * @dev    Returns an empty array if the `listId` is invalid or the list is empty.
     *
     * @param  listId  The ID of the Pair Token Whitelist.
     * @return tokens  An array containing all addresses in the specified list.
     */
    function getPairTokensInList(uint256 listId) external view returns (address[] memory tokens);

    /**
     * @notice Checks if a specific token is present in a given Pair Token Whitelist.
     *
     * @dev    Returns `false` if the `listId` is invalid or the token is not in the list.
     *
     * @param  listId The ID of the Pair Token Whitelist.
     * @param  token  The token address to check.
     * @return isWhitelisted True if the token is in the list, false otherwise.
     */
    function isWhitelistedPairToken(uint256 listId, address token) external view returns (bool);
    
    /**
    * @notice Creates a new, empty pair token whitelist.
    * 
    * @dev    Callable by anyone. The whitelist ID is auto-generated starting from 1, and the caller
    *         becomes the owner with full control over whitelist membership.
    * 
    * @dev    <h4>Postconditions:</h4>
    * @dev    1. A new whitelist is created with ID `_nextPairTokenListId`.
    * @dev    2. The caller is set as the owner of the new whitelist.
    * @dev    3. The next available list ID counter is incremented.
    * @dev    4. A `PairTokenWhitelistCreated` event is emitted.
    *
    * @param  whitelistName A descriptive name for the whitelist (used in events only).
    * @return listId        The ID of the newly created pair token whitelist.
    */
    function createPairTokenWhitelist(string calldata whitelistName) external returns (uint256 listId);

    /**
     * @notice Transfers ownership of the provided pair token whitelist to a new owner.
     *
     * @dev    Can only be called by the current owner of the whitelist.
     * @dev    Throws when `newOwner` is the zero address.
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Ownership stored in `_pairTokenWhitelistOwners[listId]` is updated to `newOwner`.
     * @dev    2. A `PairTokenWhitelistOwnershipTransferred` event is emitted.
     *
     * @param  listId   The ID of the pair token whitelist to transfer.
     * @param  newOwner The address of the new owner.
     */
    function transferPairTokenWhitelistOwnership(uint256 listId, address newOwner) external;

    /**
     * @notice Renounces ownership of the provided pair token whitelist, making the list immutable.
     *
     * @dev    Can only be called by the current owner of the whitelist.
     * @dev    Transfers ownership to the zero address. List contents can no longer be modified.
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Ownership stored in `_pairTokenWhitelistOwners[listId]` is updated to `address(0)`.
     * @dev    2. A `PairTokenWhitelistOwnershipTransferred` event is emitted with `newOwner` as `address(0)`.
     *
     * @param  listId The ID of the pair token whitelist to renounce ownership of.
     */
    function renouncePairTokenWhitelistOwnership(uint256 listId) external;

    /**
     * @notice Adds or removes tokens from a specified pair token whitelist.
     *
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     * @dev    Throws when any hook synchronization call fails.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. If adding, token added to `_pairTokenWhitelists[listId]` set if not already present.
     * @dev    2. If removing, token removed from `_pairTokenWhitelists[listId]` set if present.
     * @dev    3. `PairTokenWhitelistUpdated` event emitted for each successful addition or removal.
     * @dev    4. `registryUpdateWhitelistPairToken` called on each hook in `hooksToSync` array.
     *
     * @dev    <h4>Important Considerations:</h4>
     * @dev    Consider gas limits if the `tokens` array is very large.
     * @dev    Events are only emitted when actual changes occur (successful additions or removals).
     *
     * @param  listId      The ID of the pair token whitelist to update.
     * @param  tokens      An array of token addresses to add or remove.
     * @param  add         True to add tokens, false to remove tokens.
     * @param  hooksToSync An array of addresses for hooks to sync with the new whitelist.
     */
    function updatePairTokenWhitelist(
        uint256 listId,
        address[] calldata tokens,
        bool add,
        address[] calldata hooksToSync
    ) external;

    /**
     * @notice Gets the owner of a specific pool type Whitelist.
     *
     * @dev    Returns `address(0)` if the `listId` is invalid or ownership has been renounced.
     *
     * @param  listId  The ID of the pool type Whitelist.
     * @return owner   The address of the current owner.
     */
    function getPoolTypeWhitelistOwner(uint256 listId) external view returns (address owner);

    /**
     * @notice Gets all pool type addresses currently in a specific Pool Type Whitelist.
     *
     * @dev    Returns an empty array if the `listId` is invalid or the list is empty.
     *
     * @param  listId     The ID of the Pool Type Whitelist.
     * @return poolTypes  An array containing all addresses in the specified list.
     */
    function getPoolTypesInList(uint256 listId) external view returns (address[] memory poolTypes);

    /**
     * @notice Checks if a specific account is present in a given Pool Type Whitelist.
     *
     * @dev    Returns `false` if the `listId` is invalid or the account is not in the list.
     *
     * @param  listId         The ID of the Pool Type Whitelist.
     * @param  poolType       The pool type address to check.
     * @return isWhitelisted  True if the account is in the list, false otherwise.
     */
    function isWhitelistedPoolType(uint256 listId, address poolType) external view returns (bool isWhitelisted);

    /**
    * @notice Creates a new, empty pool type whitelist.
    * 
    * @dev    Callable by anyone. The whitelist ID is auto-generated starting from 1, and the caller
    *         becomes the owner with full control over whitelist membership.
    * 
    * @dev    <h4>Postconditions:</h4>
    * @dev    1. A new whitelist is created with ID `_nextPoolTypeListId`.
    * @dev    2. The caller is set as the owner of the new whitelist.
    * @dev    3. The next available list ID counter is incremented.
    * @dev    4. A `PoolTypeWhitelistCreated` event is emitted.
    *
    * @param  whitelistName A descriptive name for the whitelist (used in events only).
    * @return listId        The ID of the newly created pool type whitelist.
    */
    function createPoolTypeWhitelist(string calldata whitelistName) external returns (uint256 listId);

    /**
     * @notice Transfers ownership of the provided pool type whitelist to a new owner.
     *
     * @dev    Can only be called by the current owner of the whitelist.
     * @dev    Throws when `newOwner` is the zero address.
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Ownership stored in `_poolTypeWhitelistOwners[listId]` is updated to `newOwner`.
     * @dev    2. A `PoolTypeWhitelistOwnershipTransferred` event is emitted.
     *
     * @param  listId   The ID of the pool type whitelist to transfer.
     * @param  newOwner The address of the new owner.
     */
    function transferPoolTypeWhitelistOwnership(uint256 listId, address newOwner) external;

    /**
     * @notice Renounces ownership of the provided pool type whitelist, making the list immutable.
     *
     * @dev    Can only be called by the current owner of the whitelist.
     * @dev    Transfers ownership to the zero address. List contents can no longer be modified.
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Ownership stored in `_poolTypeWhitelistOwners[listId]` is updated to `address(0)`.
     * @dev    2. A `PoolTypeWhitelistOwnershipTransferred` event is emitted with `newOwner` as `address(0)`.
     *
     * @param  listId The ID of the pool type whitelist to renounce ownership of.
     */
    function renouncePoolTypeWhitelistOwnership(uint256 listId) external;

    /**
     * @notice Adds or removes pool types from a specified pool type whitelist.
     *
     * @dev    Throws when `listId` does not correspond to an existing list.
     * @dev    Throws when the caller is not the current owner of the whitelist.
     * @dev    Throws when any hook synchronization call fails.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. If adding, token added to `_poolTypeWhitelists[listId]` set if not already present.
     * @dev    2. If removing, token removed from `_poolTypeWhitelists[listId]` set if present.
     * @dev    3. `PoolTypeWhitelistUpdated` event emitted for each successful addition or removal.
     * @dev    4. `registryUpdateWhitelistPoolType` called on each hook in `hooksToSync` array.
     *
     * @dev    <h4>Important Considerations:</h4>
     * @dev    Consider gas limits if the `poolTypes` array is very large.
     * @dev    Events are only emitted when actual changes occur (successful additions or removals).
     *
     * @param  listId      The ID of the pool type whitelist to update.
     * @param  poolTypes   An array of pool type addresses to add or remove.
     * @param  add         True to add pool types, false to remove pool types.
     * @param  hooksToSync An array of addresses for hooks to sync with the new whitelist.
     */
    function updatePoolTypeWhitelist(
        uint256 listId,
        address[] calldata poolTypes,
        bool add,
        address[] calldata hooksToSync
    ) external;
}
