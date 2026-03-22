//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./DataTypes.sol";
import "./Errors.sol";
import "./interfaces/ICreatorHookSettingsRegistry.sol";
import "./interfaces/IAMMStandardHook.sol";

import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMM.sol";

import "@limitbreak/tm-core-lib/src/utils/access/LibOwnership.sol";
import "@limitbreak/tm-core-lib/src/utils/structs/EnumerableSet.sol";

import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  Creator Hook Settings Registry
 * @author Limit Break, Inc.
 * @notice This contract serves as the central repository for managing hook settings and master whitelists
 *         associated with tokens interacting with the Limit Break AMM. Token creators, contract owners, admins, and
 *         token contracts themselves can configure rules and whitelist memberships that control AMM behavior through 
 *         hook contracts.
 *
 * @dev    <h4>Interaction with Hook Contracts & Whitelist Desynchronization:</h4>
 *         This registry stores the master version of settings and whitelist list IDs. Hook contracts, such as
 *         AMMStandardHook, maintain their own local caches of settings and whitelist *contents*.
 * 
 * @dev    **Key Points on Desynchronization (Intended Behavior):**
 *         1. **Independent Caches:** Hook contracts do NOT automatically reflect real-time changes made to the
 *            *content* of whitelists within this registry.
 *         2. **Purpose:** This desynchronization is by design. It allows different hook contract instances
 *            (e.g., different versions or hooks with specific policies) to operate with distinct, potentially
 *            "frozen" or "versioned," views of whitelist memberships, even if those whitelists share the same
 *            `listId` in this registry. This enables strategies like:
 *               - Grandfathering rules for older hook versions.
 *               - Isolating a compromised/deprecated hook by maintaining its existing restrictive whitelist.
 *               - Rolling out new whitelist policies to specific hook instances gradually.
 *         3. **Token Settings Sync (`setTokenSettings`):** When `setTokenSettings` is called with `hooksToSync`,
 *            it pushes the `HookTokenSettings` struct (which includes `pairedTokenWhitelistId` and `lpWhitelistId`)
 *            to the specified hooks via their `registrySyncTokenSettings` function. This updates the hook's
 *            understanding of *which whitelist IDs* to use, but NOT the *content* of those whitelists.
 *         4. **Whitelist Content Sync:** For a hook to update its local cache of whitelist *contents* (the actual
 *            addresses within a list), an authorized call must be made to that specific hook's
 *            `registryUpdateWhitelistPairToken` or `registryUpdateWhitelistLpAddress` function.
 *            The authority to trigger these updates on hook instances is critical and typically managed
 *            by the whitelist owner via the `hooksToSync` parameter in the respective functions.
 *
 * @dev    **Security Considerations:**
 *         - Whitelist ownership can be renounced (transferred to address(0)), making lists immutable
 *         - Token settings require elevated permissions (owner/admin/contract itself)
 *         - Hook synchronization is explicit and controlled by the caller
 *         - Administrators and token creators should be aware that changes to whitelist content in this registry
 *           require a separate, explicit step to propagate those changes to the caches of relevant hook instances.
 */
contract CreatorHookSettingsRegistry is ICreatorHookSettingsRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev The address of the AMM contract.
    address private immutable AMM;

    /// @dev Core settings for each token
    mapping(address => HookTokenSettings) private _tokenSettings;

    /// @dev Set of whitelisted pair token addresses for each whitelist ID
    mapping(uint256 whitelistId => EnumerableSet.AddressSet) private _pairTokenWhitelists;

    /// @dev Set of whitelisted LP addresses for each whitelist ID
    mapping(uint256 whitelistId => EnumerableSet.AddressSet) private _lpWhitelists;

    /// @notice Set of whitelisted pool type addresses for each whitelist ID
    mapping(uint256 => EnumerableSet.AddressSet) private _poolTypeWhitelists;

    /// @dev Owner address for each pair token whitelist
    mapping(uint256 whitelistId => address) private _pairTokenWhitelistOwners;

    /// @dev Owner address for each LP whitelist
    mapping(uint256 whitelistId => address) private _lpWhitelistOwners;

    /// @dev Owner address for each pool type whitelist
    mapping(uint256 whitelistId => address) private _poolTypeWhitelistOwners;
    
    /// @dev Extensible storage for variable-length data associated with tokens. Allows storing additional
    ///      configuration data beyond the core HookTokenSettings struct using arbitrary bytes32 keys.
    mapping (address token => mapping (bytes32 extension => bytes data)) private _tokenSettingsExtensionData;

    /// @dev Extensible storage for 32-byte words associated with tokens. Allows storing additional
    ///      configuration values beyond the core HookTokenSettings struct using arbitrary bytes32 keys.
    mapping (address token => mapping (bytes32 extension => bytes32 word)) private _tokenSettingsExtensionWords;

    /// @dev Pricing bounds for each pair token
    mapping (address token => mapping(address pairToken => PricingBounds)) private _pricingBounds;

    /// @dev Pool disabled settings set by the tokens paired tokens in the pool.
    mapping (bytes32 poolId => uint256) private _disabledPools;

    /// @dev Next available ID for pair token whitelists, starting from 1
    uint56 private _nextPairTokenListId;
    /// @dev Next available ID for LP whitelists, starting from 1
    uint56 private _nextLpListId;
    /// @dev Next available ID for pool type whitelists, starting from 1
    uint56 private _nextPoolTypeListId;

    /// @dev Constant representation of list id 1
    uint256 private constant LIST_ID_ONE = 1;
    /// @dev Constant representation of the list id 1 name string
    string private constant DEFAULT_LIST_NAME = "Default List";
    /// @dev Constant representation of the next list id to set during contract construction
    uint56 private constant INITIAL_NEXT_LIST_ID = 2;
    /// @dev Constant representation of an enabled pool.
    uint256 private constant POOL_ENABLED = 0;
    /// @dev Flag set when token0 disables the pool.
    uint256 private constant POOL_DISABLED_TOKEN_0_FLAG = 1 << 0;
    /// @dev Flag set when token1 disables the pool.
    uint256 private constant POOL_DISABLED_TOKEN_1_FLAG = 1 << 1;

    constructor(address _amm, address _listIdOneOwner) {
        AMM = _amm;

        // Initialize the next list IDs to 2 as 0 is reserved for no list associated and 1 is assigned to `_listIdOneOwner`
        _nextPairTokenListId = INITIAL_NEXT_LIST_ID;
        _nextLpListId = INITIAL_NEXT_LIST_ID;
        _nextPoolTypeListId = INITIAL_NEXT_LIST_ID;

        _pairTokenWhitelistOwners[LIST_ID_ONE] = _listIdOneOwner;
        emit PairTokenWhitelistCreated(LIST_ID_ONE, _listIdOneOwner, DEFAULT_LIST_NAME);

        _lpWhitelistOwners[LIST_ID_ONE] = _listIdOneOwner;
        emit LpWhitelistCreated(LIST_ID_ONE, _listIdOneOwner, DEFAULT_LIST_NAME);

        _poolTypeWhitelistOwners[LIST_ID_ONE] = _listIdOneOwner;
        emit PoolTypeWhitelistCreated(LIST_ID_ONE, _listIdOneOwner, DEFAULT_LIST_NAME);
    }

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
    function createPairTokenWhitelist(string calldata whitelistName) external returns (uint256 listId) {
        address listCreator = msg.sender;
        unchecked {
            listId = _nextPairTokenListId++;
        }
        _pairTokenWhitelistOwners[listId] = listCreator;
        emit PairTokenWhitelistCreated(listId, listCreator, whitelistName);
    }

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
    function createLpWhitelist(string calldata whitelistName) external returns (uint256 listId) {
        address listCreator = msg.sender;
        unchecked {
            listId = _nextLpListId++;
        }
        _lpWhitelistOwners[listId] = listCreator;
        emit LpWhitelistCreated(listId, listCreator, whitelistName);
    }

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
    function createPoolTypeWhitelist(string calldata whitelistName) external returns (uint256 listId) {
        address listCreator = msg.sender;
        unchecked {
          listId = _nextPoolTypeListId++;
        }
        _poolTypeWhitelistOwners[listId] = listCreator;
        emit PoolTypeWhitelistCreated(listId, listCreator, whitelistName);
    }

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
    function transferPairTokenWhitelistOwnership(uint256 listId, address newOwner) external {
        if (newOwner == address(0)) {
            revert CreatorHookSettingsRegistry__InvalidOwner();
        }

        _reassignOwnershipOfPairTokenWhitelist(listId, newOwner);
    }

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
    function transferPoolTypeWhitelistOwnership(uint256 listId, address newOwner) external {
        if (newOwner == address(0)) {
            revert CreatorHookSettingsRegistry__InvalidOwner();
        }

        _reassignOwnershipOfPoolTypeWhitelist(listId, newOwner);
    }

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
    function renouncePairTokenWhitelistOwnership(uint256 listId) external {
        _reassignOwnershipOfPairTokenWhitelist(listId, address(0));
    }

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
    function renouncePoolTypeWhitelistOwnership(uint256 listId) external {
        _reassignOwnershipOfPoolTypeWhitelist(listId, address(0));
    }

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
    function transferLpWhitelistOwnership(uint256 listId, address newOwner) external {
        if (newOwner == address(0)) {
            revert CreatorHookSettingsRegistry__InvalidOwner();
        }

        _reassignOwnershipOfLpWhitelist(listId, newOwner);
    }

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
    function renounceLpWhitelistOwnership(uint256 listId) external {
        _reassignOwnershipOfLpWhitelist(listId, address(0));
    }
    
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
    ) external {
        LibOwnership.requireCallerIsTokenOrContractOwnerOrAdmin(token);

        if (
            settings.pairedTokenWhitelistId >= _nextPairTokenListId ||
            settings.lpWhitelistId >= _nextLpListId ||
            settings.poolTypeWhitelistId >= _nextPoolTypeListId
        ) {
            revert CreatorHookSettingsRegistry__InvalidListId();
        }

        HookTokenSettings memory memSettings = settings;
        memSettings.initialized = true;
        _tokenSettings[token] = memSettings;

        if (dataExtensions.length > 0) {
            mapping (bytes32 => bytes) storage ptrSettingsForToken = _tokenSettingsExtensionData[token];

            for (uint256 i = 0; i < dataExtensions.length; ++i) {
                ptrSettingsForToken[dataExtensions[i]] = dataSettings[i];
            }
        }

        if (wordExtensions.length > 0) {
            mapping (bytes32 => bytes32) storage ptrSettingsForToken = _tokenSettingsExtensionWords[token];

            for (uint256 i = 0; i < wordExtensions.length; ++i) {
                ptrSettingsForToken[wordExtensions[i]] = wordSettings[i];
            }
        }

        for (uint256 i = 0; i < hooksToSync.length; ++i) {
            IAMMStandardHook(hooksToSync[i]).registryUpdateTokenSettings(token, settings);
        }

        emit TokenSettingsSet(token, memSettings);
    }
    
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
    ) external {
        LibOwnership.requireCallerIsTokenOrContractOwnerOrAdmin(token);

        PoolState memory poolState = ILimitBreakAMM(AMM).getPoolState(poolId);

        uint256 initialDisabledState = _disabledPools[poolId];
        uint256 newDisabledState = initialDisabledState;

        if (token == poolState.token0) {
            if (disable) {
                newDisabledState = newDisabledState | POOL_DISABLED_TOKEN_0_FLAG;
            } else {
                newDisabledState = newDisabledState & POOL_DISABLED_TOKEN_1_FLAG;
            }
        } else if (token == poolState.token1) {
            if (disable) {
                newDisabledState = newDisabledState | POOL_DISABLED_TOKEN_1_FLAG;
            } else {
                newDisabledState = newDisabledState & POOL_DISABLED_TOKEN_0_FLAG;
            }
        } else {
            revert CreatorHookSettingsRegistry__TokenIsNotInPair();
        }

        _disabledPools[poolId] = newDisabledState;

        if (initialDisabledState == POOL_ENABLED && disable) {
            emit PoolDisabled(poolId);
        } else if (initialDisabledState != POOL_ENABLED && newDisabledState == POOL_ENABLED) {
            emit PoolEnabled(poolId);
        }
    }

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
     * @param  token            The token address for which pricing bounds are being set.
     * @param  pairTokens       An array of pair token addresses.
     * @param  minSqrtPricesX96 An array of minimum square root prices for each pair token.
     * @param  maxSqrtPricesX96 An array of maximum square root prices for each pair token.
     * @param  hooksToSync      An array of addresses for hooks to sync with the new pricing bounds.
     */
    function setPricingBounds(
        address token,
        address[] calldata pairTokens,
        uint160[] calldata minSqrtPricesX96,
        uint160[] calldata maxSqrtPricesX96,
        address[] calldata hooksToSync
    ) external {
        LibOwnership.requireCallerIsTokenOrContractOwnerOrAdmin(token);

        if (pairTokens.length != minSqrtPricesX96.length || minSqrtPricesX96.length != maxSqrtPricesX96.length) {
            revert CreatorHookSettingsRegistry__LengthOfProvidedArraysMismatch();
        }

        mapping(address => PricingBounds) storage ptrPricingBounds = _pricingBounds[token];
        address pairToken;
        uint160 minSqrtPriceX96;
        uint160 maxSqrtPriceX96;
        for (uint256 i = 0; i < pairTokens.length; ++i) {
            pairToken = pairTokens[i];
            minSqrtPriceX96 = minSqrtPricesX96[i];
            maxSqrtPriceX96 = maxSqrtPricesX96[i];

            if (minSqrtPriceX96 > maxSqrtPriceX96 && maxSqrtPriceX96 != 0) {
                revert CreatorHookSettingsRegistry__MaxPriceMustBeGreaterThanOrEqualToMinPrice();
            }

            if (minSqrtPriceX96 | maxSqrtPriceX96 == 0) {
                // Pricing bound being unset
                ptrPricingBounds[pairToken] =
                    PricingBounds({isSet: false, minSqrtPriceX96: minSqrtPriceX96, maxSqrtPriceX96: maxSqrtPriceX96});

                emit PricingBoundsUnset(token, pairToken);
            } else {
                // Pricing bound being set
                ptrPricingBounds[pairToken] =
                    PricingBounds({isSet: true, minSqrtPriceX96: minSqrtPriceX96, maxSqrtPriceX96: maxSqrtPriceX96});

                emit PricingBoundsSet(token, pairToken, minSqrtPriceX96, maxSqrtPriceX96);
            }
        }

        for (uint256 i = 0; i < hooksToSync.length; ++i) {
            IAMMStandardHook(hooksToSync[i]).registryUpdatePricingBounds(token, pairTokens, minSqrtPricesX96, maxSqrtPricesX96);
        }
    }

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
    ) external {
        LibOwnership.requireCallerIsTokenOrContractOwnerOrAdmin(token);

        if (expansionWords.length > 0) {
            mapping (bytes32 => bytes32) storage ptrExpansionWordsForToken = _tokenSettingsExtensionWords[token];

            for (uint256 i = 0; i < expansionWords.length; ++i) {
                ptrExpansionWordsForToken[expansionWords[i].key] = expansionWords[i].value;

                emit ExpansionWordsSet(token, expansionWords[i].key, expansionWords[i].value);
            }
        }

        if (expansionDatums.length > 0) {
            mapping (bytes32 => bytes) storage ptrExpansionDatumsForToken = _tokenSettingsExtensionData[token];

            for (uint256 i = 0; i < expansionDatums.length; ++i) {
                ptrExpansionDatumsForToken[expansionDatums[i].key] = expansionDatums[i].value;

                emit ExpansionDatumsSet(token, expansionDatums[i].key, expansionDatums[i].value);
            }
        }
    }

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
    ) external {
        _requireCallerOwnsPairTokenWhitelist(listId);

        EnumerableSet.AddressSet storage list = _pairTokenWhitelists[listId];
        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            if (add) {
                if (list.add(token)) emit PairTokenWhitelistUpdated(listId, token, true);
            } else {
                if (list.remove(token)) emit PairTokenWhitelistUpdated(listId, token, false);
            }
        }

        for (uint256 i = 0; i < hooksToSync.length; ++i) {
            IAMMStandardHook(hooksToSync[i]).registryUpdateWhitelistPairToken(listId, tokens, add);
        }
    }

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
    ) external {
        _requireCallerOwnsPoolTypeWhitelist(listId);

        EnumerableSet.AddressSet storage list = _poolTypeWhitelists[listId];
        for (uint256 i = 0; i < poolTypes.length; ++i) {
            address poolType = poolTypes[i];
            if (add) {
                if (list.add(poolType)) emit PoolTypeWhitelistUpdated(listId, poolType, true);
            } else {
                if (list.remove(poolType)) emit PoolTypeWhitelistUpdated(listId, poolType, false);
            }
        }

        for (uint256 i = 0; i < hooksToSync.length; ++i) {
            IAMMStandardHook(hooksToSync[i]).registryUpdateWhitelistPoolType(listId, poolTypes, add);
        }
    }

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
    ) external {
        _requireCallerOwnsLpWhitelist(listId);

        EnumerableSet.AddressSet storage list = _lpWhitelists[listId];
        for (uint256 i = 0; i < accounts.length; ++i) {
            address account = accounts[i];
            if (add) {
                if (list.add(account)) emit LpWhitelistUpdated(listId, account, true);
            } else {
                if (list.remove(account)) emit LpWhitelistUpdated(listId, account, false);
            }
        }

        for (uint256 i = 0; i < hooksToSync.length; ++i) {
            IAMMStandardHook(hooksToSync[i]).registryUpdateWhitelistLpAddress(listId, accounts, add);
        }
    }

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
    function getPriceBounds(address token, address pairToken) external view returns (PricingBounds memory bounds) {
        bounds = _pricingBounds[token][pairToken];
    }

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
    ) external view returns (bytes[] memory data) {
        if(extensions.length > 0) {
            mapping (bytes32 => bytes) storage ptrSettingsForToken = _tokenSettingsExtensionData[token];

            data = new bytes[](extensions.length);
            for (uint256 i = 0; i < extensions.length; ++i) {
                data[i] = ptrSettingsForToken[extensions[i]];
            }
        }
    }

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
    ) external view returns (bytes32[] memory words) {
        if(extensions.length > 0) {
            mapping (bytes32 => bytes32) storage ptrSettingsForToken = _tokenSettingsExtensionWords[token];

            words = new bytes32[](extensions.length);
            for (uint256 i = 0; i < extensions.length; ++i) {
                words[i] = ptrSettingsForToken[extensions[i]];
            }
        }
    }

    /**
     * @notice Gets the owner of a specific Pair Token Whitelist.
     *
     * @dev    Returns `address(0)` if the `listId` is invalid or ownership has been renounced.
     *
     * @param  listId The ID of the Pair Token Whitelist.
     * @return owner  The address of the current owner.
     */
    function getPairTokenWhitelistOwner(uint256 listId) external view override returns (address owner) {
        owner = _pairTokenWhitelistOwners[listId];
    }

    /**
     * @notice Gets the owner of a specific LP Whitelist.
     *
     * @dev    Returns `address(0)` if the `listId` is invalid or ownership has been renounced.
     *
     * @param  listId The ID of the LP Whitelist.
     * @return owner  The address of the current owner.
     */
    function getLpWhitelistOwner(uint256 listId) external view override returns (address owner) {
        owner = _lpWhitelistOwners[listId];
    }

    /**
     * @notice Gets the owner of a specific pool type Whitelist.
     *
     * @dev    Returns `address(0)` if the `listId` is invalid or ownership has been renounced.
     *
     * @param  listId  The ID of the pool type Whitelist.
     * @return owner   The address of the current owner.
     */
    function getPoolTypeWhitelistOwner(uint256 listId) external view returns (address owner) {
        owner = _poolTypeWhitelistOwners[listId];
    }

    /**
     * @notice Gets all token addresses currently in a specific Pair Token Whitelist.
     *
     * @dev    Returns an empty array if the `listId` is invalid or the list is empty.
     *
     * @param  listId  The ID of the Pair Token Whitelist.
     * @return tokens  An array containing all addresses in the specified list.
     */
    function getPairTokensInList(uint256 listId) external view override returns (address[] memory tokens) {
        tokens = _pairTokenWhitelists[listId].values();
    }

    /**
     * @notice Gets all pool type addresses currently in a specific Pool Type Whitelist.
     *
     * @dev    Returns an empty array if the `listId` is invalid or the list is empty.
     *
     * @param  listId     The ID of the Pool Type Whitelist.
     * @return poolTypes  An array containing all addresses in the specified list.
     */
    function getPoolTypesInList(uint256 listId) external view returns (address[] memory poolTypes) {
        poolTypes = _poolTypeWhitelists[listId].values();
    }

    /**
     * @notice Gets all account addresses currently in a specific LP Whitelist.
     *
     * @dev    Returns an empty array if the `listId` is invalid or the list is empty.
     *
     * @param  listId   The ID of the LP Whitelist.
     * @return accounts An array containing all addresses in the specified list.
     */
    function getLpsInList(uint256 listId) external view override returns (address[] memory accounts) {
        accounts = _lpWhitelists[listId].values();
    }

    /**
     * @notice Checks if a specific token is present in a given Pair Token Whitelist.
     *
     * @dev    Returns `false` if the `listId` is invalid or the token is not in the list.
     *
     * @param  listId The ID of the Pair Token Whitelist.
     * @param  token  The token address to check.
     * @return isWhitelisted True if the token is in the list, false otherwise.
     */
    function isWhitelistedPairToken(uint256 listId, address token) external view returns (bool isWhitelisted) {
        isWhitelisted = _pairTokenWhitelists[listId].contains(token);
    }

    /**
     * @notice Checks if a specific account is present in a given LP Whitelist.
     *
     * @dev    Returns `false` if the `listId` is invalid or the account is not in the list.
     *
     * @param  listId  The ID of the LP Whitelist.
     * @param  account The account address to check.
     * @return isWhitelisted True if the account is in the list, false otherwise.
     */
    function isWhitelistedLp(uint256 listId, address account) external view returns (bool isWhitelisted) {
        isWhitelisted = _lpWhitelists[listId].contains(account);
    }

    /**
     * @notice Checks if a specific account is present in a given Pool Type Whitelist.
     *
     * @dev    Returns `false` if the `listId` is invalid or the account is not in the list.
     *
     * @param  listId         The ID of the Pool Type Whitelist.
     * @param  poolType       The pool type address to check.
     * @return isWhitelisted  True if the account is in the list, false otherwise.
     */
    function isWhitelistedPoolType(uint256 listId, address poolType) external view returns (bool isWhitelisted) {
        isWhitelisted = _poolTypeWhitelists[listId].contains(poolType);
    }

    /**
     * @notice Retrieves the hook settings for a specific token.
     *
     * @dev    Callers should check the `initialized` flag within the returned struct.
     *
     * @param  token         The token address.
     * @return tokenSettings The HookTokenSettings struct containing comprehensive token configuration including fees, 
     *                       trading controls, whitelists, and operational parameters. See `DataTypes.sol` for field details.
     */
    function getTokenSettings(address token) external view returns (HookTokenSettings memory tokenSettings) {
        tokenSettings = _tokenSettings[token];
    }

    /**
     * @notice Checks if the specified poolId is disabled.
     *
     * @param  poolId   ID of the pool to check if it is disabled.
     * @return disabled True if the pool is disabled by either token in the pair.
     */
    function isPoolDisabled(bytes32 poolId) external view returns (bool disabled) {
        disabled = _disabledPools[poolId] != POOL_ENABLED;
    }

    /**
     * @notice Checks if settings for a specific token have been initialized in this registry.
     *
     * @dev    Checks the `initialized` flag within the stored `HookTokenSettings` struct.
     *
     * @param  token The token address.
     * @return isInitialized True if settings have been set via `setTokenSettings`, false otherwise.
     */
    function isTokenInitialized(address token) external view returns (bool isInitialized) {
        isInitialized = _tokenSettings[token].initialized;
    }

    /**
     * @notice Internal helper function to reassign ownership of an LP Whitelist.
     *
     * @dev    Throws when `listId` is invalid.
     * @dev    Throws when the caller is not the current owner.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. `_lpWhitelistOwners[listId]` updated to `newOwner`.
     * @dev    2. `LpWhitelistOwnershipTransferred` event emitted.
     *
     * @param  listId   The ID of the list.
     * @param  newOwner The address of the new owner (can be address(0) for renouncing).
     */
    function _reassignOwnershipOfLpWhitelist(uint256 listId, address newOwner) internal {
        _requireCallerOwnsLpWhitelist(listId);
        address currentOwner = _lpWhitelistOwners[listId];
        _lpWhitelistOwners[listId] = newOwner;
        emit LpWhitelistOwnershipTransferred(listId, currentOwner, newOwner);
    }

    /**
     * @notice Internal helper function to reassign ownership of a pair token whitelist.
     *
     * @dev    Throws when the caller is not the current owner of the provided pair token whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. `_pairTokenWhitelistOwners[listId]` updated to `newOwner`.
     * @dev    2. `PairTokenWhitelistOwnershipTransferred` event emitted.
     *
     * @param  listId   The ID of the list.
     * @param  newOwner The address of the new owner (can be address(0) for renouncing).
     */
    function _reassignOwnershipOfPairTokenWhitelist(uint256 listId, address newOwner) internal {
        _requireCallerOwnsPairTokenWhitelist(listId);
        address currentOwner = _pairTokenWhitelistOwners[listId];
        _pairTokenWhitelistOwners[listId] = newOwner;
        emit PairTokenWhitelistOwnershipTransferred(listId, currentOwner, newOwner);
    }

    /**
     * @notice Internal helper function to reassign ownership of a pool type whitelist.
     *
     * @dev    Throws when the caller is not the current owner of the provided pool type whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. `_poolTypeWhitelistOwners[listId]` updated to `newOwner`.
     * @dev    2. `PoolTypeWhitelistOwnershipTransferred` event emitted.
     *
     * @param  listId   The ID of the list.
     * @param  newOwner The address of the new owner (can be address(0) for renouncing).
     */
    function _reassignOwnershipOfPoolTypeWhitelist(uint256 listId, address newOwner) internal {
        _requireCallerOwnsPoolTypeWhitelist(listId);
        address currentOwner = _poolTypeWhitelistOwners[listId];
        _poolTypeWhitelistOwners[listId] = newOwner;
        emit PoolTypeWhitelistOwnershipTransferred(listId, currentOwner, newOwner);
    }

    /**
     * @notice Internal function that checks if the caller owns the specified pair token whitelist.
     *
     * @dev    Throws when caller is not the current owner of the whitelist.
     * @dev    Implicitly checks list existence, as owner mapping would be `address(0)` if non-existent/renounced.
     *
     * @param pairTokenWhitelistId The ID of the pair token whitelist to check ownership for.
     */
    function _requireCallerOwnsPairTokenWhitelist(uint256 pairTokenWhitelistId) internal view {
        if (msg.sender != _pairTokenWhitelistOwners[pairTokenWhitelistId]) {
            revert CreatorHookSettingsRegistry__CallerDoesNotOwnPairTokenWhitelist();
        }
    }

    /**
     * @notice Internal function that checks if the caller owns the specified pool type whitelist.
     *
     * @dev    Throws when caller is not the current owner of the whitelist.
     * @dev    Implicitly checks list existence, as owner mapping would be `address(0)` if non-existent/renounced.
     *
     * @param poolTypeWhitelistId The ID of the pool type whitelist to check ownership for.
     */
    function _requireCallerOwnsPoolTypeWhitelist(uint256 poolTypeWhitelistId) internal view {
        if (msg.sender != _poolTypeWhitelistOwners[poolTypeWhitelistId]) {
            revert CreatorHookSettingsRegistry__CallerDoesNotOwnPoolTypeWhitelist();
        }
    }

    /**
     * @notice Internal function that checks if the caller owns the specified LP whitelist.
     *
     * @dev    Throws when caller is not the current owner of the whitelist.
     * @dev    Implicitly checks list existence, as owner mapping would be `address(0)` if non-existent/renounced.
     *
     * @param lpWhitelistId The ID of the LP whitelist to check ownership for.
     */
    function _requireCallerOwnsLpWhitelist(uint256 lpWhitelistId) internal view {
        if (msg.sender != _lpWhitelistOwners[lpWhitelistId]) {
            revert CreatorHookSettingsRegistry__CallerDoesNotOwnLpWhitelist();
        }
    }
}
