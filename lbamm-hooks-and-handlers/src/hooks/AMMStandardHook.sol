//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./DataTypes.sol";
import "./Errors.sol";
import "./interfaces/IAMMStandardHook.sol";
import "./interfaces/ICreatorHookSettingsRegistry.sol";
import "./libraries/SqrtPriceCalculator.sol";

import "@limitbreak/lb-amm-core/src/Constants.sol";
import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMMPoolType.sol";
import "@limitbreak/lb-amm-core/src/libraries/PoolDecoder.sol";

import "@limitbreak/tm-core-lib/src/utils/math/FullMath.sol";
import "@limitbreak/tm-core-lib/src/utils/misc/Tstorish.sol";
import "@limitbreak/tm-core-lib/src/utils/structs/EnumerableSet.sol";
import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  AMM Standard Hook
 * @author Limit Break, Inc.
 * @notice A hook implementation for the Limit Break AMM system that enforces token-specific trading rules,
 *         fee calculations, whitelist restrictions, and liquidity controls. This hook manages settings for individual
 *         tokens including fee structures, LP whitelists, and pair token restrictions.
 *
 * @dev    This contract implements the IAMMStandardHook interface and integrates with the CreatorHookSettingsRegistry
 *         to provide centralized management of token settings. It supports multiple hook functions including beforeSwap,
 *         afterSwap, liquidity modification validation, and pool creation validation. The hook caches settings locally
 *         for gas efficiency while maintaining synchronization with the registry.
 */
contract AMMStandardHook is IAMMStandardHook, Tstorish {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev The address of the AMM contract.
    address private immutable AMM;

    /// @dev Mapping of token addresses to their cached hook settings
    mapping(address => HookTokenSettings) private _tokenSettings;

    /// @dev Mapping of whitelist IDs to sets of allowed pair token addresses
    mapping(uint256 => EnumerableSet.AddressSet) private _pairTokenWhitelists;

    /// @dev Mapping of whitelist IDs to sets of allowed liquidity provider addresses
    mapping(uint256 => EnumerableSet.AddressSet) private _lpWhitelists;

    /// @dev Mapping of whitelist IDs to sets of allowed pool addresses
    mapping(uint256 => EnumerableSet.AddressSet) private _poolTypeWhitelists;

    /// @dev Mapping of token addresses to their pricing bounds for specific pair tokens
    /// @dev    First key is the token, second key is the pair token, value contains min/max price bounds
    mapping(address => mapping(address => PricingBounds)) private _pricingBounds;

    /// @dev Flags of hook functions that this contract supports (optional implementations)
    uint32 private constant _supportedHookFlags = TOKEN_SETTINGS_BEFORE_SWAP_HOOK_FLAG
        | TOKEN_SETTINGS_AFTER_SWAP_HOOK_FLAG | TOKEN_SETTINGS_ADD_LIQUIDITY_HOOK_FLAG
        | TOKEN_SETTINGS_POOL_CREATION_HOOK_FLAG | TOKEN_SETTINGS_HANDLER_ORDER_VALIDATE_FLAG
        | TOKEN_SETTINGS_FLASHLOANS_FLAG | TOKEN_SETTINGS_FLASHLOANS_VALIDATE_FEE_FLAG;

    /// @dev Flags of hook functions that this contract requires (mandatory implementations)
    uint32 private constant _requiredHookFlags = 0;

    /// @dev Constant value for no hook fees to be returned in add liquidity hook function.
    uint256 private constant NO_HOOK_FEE = 0;

    /// @dev Constant value of the storage slot pointer for direct swap before swap amounts for use in tstorish.
    uint256 private constant DIRECT_SWAP_BEFORE_SWAP_AMOUNT_SLOT = 0xFFFFFFFFFFFFFFFF;

    bytes32 private constant DIRECT_SWAP_POOL_ID = bytes32(0);

    /// @dev Reference to the registry contract that stores the authoritative token settings
    ICreatorHookSettingsRegistry private immutable SETTINGS_REGISTRY;

    constructor(address _amm, address creatorHookSettingsRegistry_) {
        if (_amm == address(0) || creatorHookSettingsRegistry_ == address(0)) {
            revert AMMStandardHook__InvalidAddress();
        }

        AMM = _amm;
        SETTINGS_REGISTRY = ICreatorHookSettingsRegistry(creatorHookSettingsRegistry_);
    }

    ///////////////////////////////////////////////////////
    //                  HOOK FUNCTIONS                   //
    ///////////////////////////////////////////////////////

    /**
     * @notice Enforces swap controls and calculates fees on the specified token for a swap before execution.
     *
     * @dev    Throws when trading is paused for either token involved in the swap.
     * @dev    Throws if the current price is below the minimum or above the maximum allowed bounds.
     *            If the swap is in a direction that moves back towards the price limit, it will not revert.
     *
     * @dev    Fetches or retrieves cached settings for both input and output tokens, validates all trading
     *         rules including pause status, and calculates the appropriate fee based on whether this
     *         is an input-based or output-based swap.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Token settings have been fetched and cached if not already present.
     * @dev    2. Trading rules have been validated for the context token.
     * @dev    3. Input fee has been calculated based on the appropriate fee rates.
     *
     * @param  swapParams Specific parameters for the swap including amount and direction.
     * @return fee   The calculated fee amount in terms of the specified token.
     */
    function beforeSwap(
        SwapContext calldata /*context*/,
        HookSwapParams calldata swapParams,
        bytes calldata /*hookData*/
    ) external returns (uint256 fee) {
        _requireCallerIsAMM();

        (address token, address pairedToken) =
            swapParams.hookForInputToken ? (swapParams.tokenIn, swapParams.tokenOut) : (swapParams.tokenOut, swapParams.tokenIn);
        HookTokenSettings memory tokenSettings = _getOrFetchTokenSettings(token);

        _checkPoolEnabled(tokenSettings, swapParams.poolId);
        _validateTokenTradingRules(tokenSettings, swapParams, pairedToken);
        _validatePricingBounds(swapParams, token, pairedToken, true);

        if (swapParams.inputSwap) {
            if (swapParams.hookForInputToken) {
                fee = _calculateFee(swapParams.amount, tokenSettings.tokenFeeSellBPS);
            } else {
                fee = _calculateFee(swapParams.amount, tokenSettings.pairedFeeBuyBPS);
            }
        } else {
            if (swapParams.hookForInputToken) {
                fee = _calculateFee(swapParams.amount, tokenSettings.pairedFeeSellBPS);
            } else {
                fee = _calculateFee(swapParams.amount, tokenSettings.tokenFeeBuyBPS);
            }
        }
    }

    /**
     * @notice Calculates the fee for a swap after execution and enforces token settings.
     *
     * @dev    Throws when trading is paused for either token involved in the swap.
     * @dev    Throws if the current price is below the minimum or above the maximum allowed bounds.
     *            If the swap is in a direction that moves back towards the price limit, it will not revert.
     *
     * @dev    Fetches or retrieves cached settings for both input and output tokens, validates all trading
     *         rules including price bounds and calculates the appropriate fee based on whether this
     *         is an input-based or output-based swap.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Token settings have been fetched and cached if not already present.
     * @dev    2. Trading rules have been validated for the context token.
     * @dev    3. Output fee has been calculated based on the appropriate fee rates.
     *
     * @param  swapParams Specific parameters for the swap including amount and direction.
     * @return fee  The calculated fee amount in terms of the unspecified token.
     */
    function afterSwap(
        SwapContext calldata /*context*/,
        HookSwapParams calldata swapParams,
        bytes calldata /*hookData*/
    ) external returns (uint256 fee) {
        _requireCallerIsAMM();
        
        (address token, address pairedToken) =
            swapParams.hookForInputToken ? (swapParams.tokenIn, swapParams.tokenOut) : (swapParams.tokenOut, swapParams.tokenIn);
        HookTokenSettings memory tokenSettings = _getOrFetchTokenSettings(token);

        _checkPoolEnabled(tokenSettings, swapParams.poolId);
        _validateTokenTradingRules(tokenSettings, swapParams, pairedToken);
        _validatePricingBounds(swapParams, token, pairedToken, false);

        if (swapParams.inputSwap) {
            if (swapParams.hookForInputToken) {
                fee = _calculateFee(swapParams.amount, tokenSettings.pairedFeeSellBPS);
            } else {
                fee = _calculateFee(swapParams.amount, tokenSettings.tokenFeeBuyBPS);
            }
        } else {
            if (swapParams.hookForInputToken) {
                fee = _calculateFee(swapParams.amount, tokenSettings.tokenFeeSellBPS);
            } else {
                fee = _calculateFee(swapParams.amount, tokenSettings.pairedFeeBuyBPS);
            }
        }
    }

    /**
     * @notice  Validates the pricing bounds for an order placed in a transfer handler.
     * 
     * @dev     This hook will not be called by the AMM directly, it will be called by transfer
     * @dev     handlers during order creation.
     * 
     * @dev     Throws when pricing bounds are set and the calculated price is outside bounds.
     * 
     * @param hookForTokenIn  True if the hook is being called for the input token.
     * @param tokenIn         Address of the input token for the order.
     * @param tokenOut        Address of the output token for the order.
     * @param amountIn        Amount of input token for the order.
     * @param amountOut       Amount of output token for the order.
     */
    function validateHandlerOrder(
        address /*maker*/,
        bool hookForTokenIn,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bytes calldata /*handlerOrderParams*/,
        bytes calldata /*hookData*/
    ) external view {
        (address token, address pairedToken) = hookForTokenIn ? (tokenIn, tokenOut) : (tokenOut, tokenIn);

        PricingBounds memory bounds = _pricingBounds[token][pairedToken];
        if (bounds.isSet) {
            (uint256 amount0, uint256 amount1) = tokenIn < tokenOut ? 
                (amountIn, amountOut) :
                (amountOut, amountIn);
            uint160 sqrtPriceX96 = SqrtPriceCalculator.computeRatioX96(amount1, amount0);

            if (bounds.isSet) {
                if (bounds.minSqrtPriceX96 != 0 && sqrtPriceX96 < bounds.minSqrtPriceX96) {
                    revert AMMStandardHook__InvalidPrice();
                }
                if (bounds.maxSqrtPriceX96 != 0 && sqrtPriceX96 > bounds.maxSqrtPriceX96) {
                    revert AMMStandardHook__InvalidPrice();
                }
            }
        }
    }

    /**
     * @notice Validates liquidity additions against token-specific LP whitelist restrictions.
     *
     * @dev    Throws if the provider is not on the required LP whitelist.
     *
     * @dev    Fetches settings for the hook token and enforces LP whitelist restrictions.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Token settings have been fetched and cached if not already present.
     * @dev    2. LP whitelist restrictions have been validated for the provider.
     *
     * @param  hookForToken0    True if the hook is for Token0, false otherwise.
     * @param  context          General context for the liquidity modification including provider and token addresses.
     * @param  liquidityParams  Specific parameters for the liquidity modification.
     */
    function validateAddLiquidity(
        bool hookForToken0,
        LiquidityContext calldata context,
        LiquidityModificationParams calldata liquidityParams,
        uint256, /*amount0*/
        uint256, /*amount1*/
        uint256, /*fees0*/
        uint256, /*fees1*/
        bytes calldata /*hookData*/
    ) external returns (uint256, uint256) {
        _requireCallerIsAMM();

        (address token, address pairedToken) = hookForToken0 ? (context.token0, context.token1) : (context.token1, context.token0);
        HookTokenSettings memory tokenSettings = _getOrFetchTokenSettings(token);

        _checkPoolEnabled(tokenSettings, liquidityParams.poolId);
        _enforceLiquidityModificationSettings(tokenSettings, context);

        PricingBounds memory bounds = _pricingBounds[token][pairedToken];
        bytes32 poolId = liquidityParams.poolId;

        if (bounds.isSet) {
            address poolType = PoolDecoder.getPoolType(poolId);
            uint160 sqrtPriceX96 = ILimitBreakAMMPoolType(poolType).getCurrentPriceX96(AMM, poolId);

            if (bounds.isSet) {
                if (bounds.minSqrtPriceX96 != 0 && sqrtPriceX96 < bounds.minSqrtPriceX96) {
                    revert AMMStandardHook__InvalidPrice();
                }
                if (bounds.maxSqrtPriceX96 != 0 && sqrtPriceX96 > bounds.maxSqrtPriceX96) {
                    revert AMMStandardHook__InvalidPrice();
                }
            }
        }

        return (NO_HOOK_FEE, NO_HOOK_FEE);
    }

    /**
     * @notice Validates pool creation against comprehensive token-specific restrictions and settings.
     *
     * @dev    Throws if the pool type is not permitted for the token.
     * @dev    Throws if the pool fee is below the minimum required.
     * @dev    Throws if the pool fee exceeds the maximum allowed.
     * @dev    Throws if the pair token is not on the required whitelist.
     * @dev    Throws if the creator is not on the required LP whitelist.
     *
     * @dev    Fetches settings for the hook token and validates all pool creation restrictions including
     *         allowed pool types, fee constraints, pair token whitelist, pricing bounds, and LP whitelist.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Token settings have been fetched and cached if not already present.
     * @dev    2. Pool type has been validated against allowed types.
     * @dev    3. Pool fee has been validated against min/max constraints.
     * @dev    4. Pair token has been validated against whitelist restrictions.
     * @dev    5. Creator has been validated against LP whitelist restrictions.
     *
     * @param  poolId         The identifier of the pool to validate.
     * @param  creator        The address initiating the pool creation.
     * @param  hookForToken0  True if the hook is for Token0, false otherwise.
     * @param  details        Struct containing all details about the pool being created.
     */
    function validatePoolCreation(
        bytes32 poolId,
        address creator,
        bool hookForToken0,
        PoolCreationDetails calldata details,
        bytes calldata /*hookData*/
    ) external {
        _requireCallerIsAMM();
        
        (address token, address pairedToken) = hookForToken0 ? 
            (details.token0, details.token1) : 
            (details.token1, details.token0);

        _enforcePoolCreationSettings(poolId, details, pairedToken, creator, _getOrFetchTokenSettings(token));
    }

    /**
     * @notice  Prohibits a token from being flash loaned when the `TOKEN_SETTINGS_FLASHLOANS_FLAG` is set for
     *          the token on the AMM.
     * 
     * @dev     This function will always revert when called.
     */
    function beforeFlashloan(
        address,
        address,
        uint256,
        address,
        bytes calldata
    ) external pure returns (address, uint256) {
        revert AMMStandardHook__TokenNotAllowedAsFlashloan();
    }

    /**
     * @notice  Prohibits a token from being used as a flash loan fee token by other tokens being flash loaned
     *          when the `TOKEN_SETTINGS_FLASHLOANS_VALIDATE_FEE_FLAG` is set for the token on the AMM.
     * 
     * @dev     This function will always revert when called.
     */
    function validateFlashloanFee(
        address,
        address,
        uint256,
        address,
        uint256,
        address,
        bytes calldata
    ) external pure returns (bool) {
        revert AMMStandardHook__TokenNotAllowedAsFlashloanFee();
    }

    /**
     * @notice Returns the hook flags indicating required and supported hook functionalities.
     *
     * @dev    Used by the AMM core to determine which hooks to call and which are mandatory.
     *         Values are set as constants during deployment and never change.
     *
     * @return requiredFlags  Bitmask of hooks that MUST be implemented.
     * @return supportedFlags Bitmask of optional hooks implemented by this contract.
     */
    function hookFlags() external pure returns (uint32 requiredFlags, uint32 supportedFlags) {
        return (_requiredHookFlags, _supportedHookFlags);
    }

    ///////////////////////////////////////////////////////
    //                 REGISTRY FUNCTIONS                //
    ///////////////////////////////////////////////////////

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
     * @param  addPairedTokens       True to add addresses to the whitelist, false to remove them.
     */
    function registryUpdateWhitelistPairToken(
        uint256 pairTokenWhitelistId,
        address[] calldata pairTokens,
        bool addPairedTokens
    ) external {
        _requireCallerIsRegistry();

        EnumerableSet.AddressSet storage ptrPairTokens = _pairTokenWhitelists[pairTokenWhitelistId];
        if (addPairedTokens) {
            for (uint256 i = 0; i < pairTokens.length; ++i) {
                address pairToken = pairTokens[i];

                if (ptrPairTokens.add(pairToken)) {
                    emit PairTokenAddedToWhitelist(pairTokenWhitelistId, pairToken);
                }
            }
        } else {
            for (uint256 i = 0; i < pairTokens.length; ++i) {
                address pairToken = pairTokens[i];

                if (ptrPairTokens.remove(pairToken)) {
                    emit PairTokenRemovedFromWhitelist(pairTokenWhitelistId, pairToken);
                }
            }
        }
    }

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
    ) external {
        _requireCallerIsRegistry();

        EnumerableSet.AddressSet storage ptrPoolTypes = _poolTypeWhitelists[poolTypeWhitelistId];
        if (poolTypesAdded) {
            for (uint256 i = 0; i < poolTypes.length; ++i) {
                address poolType = poolTypes[i];

                if (ptrPoolTypes.add(poolType)) {
                    emit PoolTypeAddedToWhitelist(poolTypeWhitelistId, poolType);
                }
            }
        } else {
            for (uint256 i = 0; i < poolTypes.length; ++i) {
                address poolType = poolTypes[i];

                if (ptrPoolTypes.remove(poolType)) {
                    emit PoolTypeRemovedFromWhitelist(poolTypeWhitelistId, poolType);
                }
            }
        }
    }

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
    ) external {
        _requireCallerIsRegistry();

        EnumerableSet.AddressSet storage ptrLpWl = _lpWhitelists[lpWhitelistId];
        if (lpAddressesAdded) {
            for (uint256 i = 0; i < lpAddresses.length; ++i) {
                address lpAddress = lpAddresses[i];

                if (ptrLpWl.add(lpAddress)) {
                    emit LpAddressAddedtoWhitelist(lpWhitelistId, lpAddress);
                }
            }
        } else {
            for (uint256 i = 0; i < lpAddresses.length; ++i) {
                address lpAddress = lpAddresses[i];

                if (ptrLpWl.remove(lpAddress)) {
                    emit LpAddressRemovedFromWhitelist(lpWhitelistId, lpAddress);
                }
            }
        }
    }

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
    function registryUpdateTokenSettings(address token, HookTokenSettings calldata tokenSettings) external {
        _requireCallerIsRegistry();

        _tokenSettings[token] = tokenSettings;

        emit TokenSettingsUpdated(token, tokenSettings);
    }

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
     * @param  token              The address of the token for which pricing bounds are being set.
     * @param  pairTokens         Array of pair token addresses that will have bounds set against the main token.
     * @param  minSqrtPricesX96   Array of minimum square root prices in X96 format corresponding to each pair token.
     * @param  maxSqrtPricesX96   Array of maximum square root prices in X96 format corresponding to each pair token.
     */
    function registryUpdatePricingBounds(
        address token,
        address[] calldata pairTokens,
        uint160[] calldata minSqrtPricesX96,
        uint160[] calldata maxSqrtPricesX96
    ) external {
        _requireCallerIsRegistry();

        mapping(address => PricingBounds) storage ptrPricingBounds = _pricingBounds[token];
        address pairToken;
        uint160 minSqrtPriceX96;
        uint160 maxSqrtPriceX96;
        for (uint256 i = 0; i < pairTokens.length; ++i) {
            pairToken = pairTokens[i];
            minSqrtPriceX96 = minSqrtPricesX96[i];
            maxSqrtPriceX96 = maxSqrtPricesX96[i];

            if (minSqrtPriceX96 > maxSqrtPriceX96 && maxSqrtPriceX96 != 0) {
                revert AMMStandardHook__MaxPriceMustBeGreaterThanOrEqualToMinPrice();
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
    }

    /**
     * @notice  Returns the manifest URI for the token hook to provide app integrations with
     *          information necessary to process transactions that utilize the token hook.
     * 
     * @dev     Hook developers **MUST** emit a `TokenHookManifestUriUpdated` event if the URI
     *          changes.
     * 
     * @return  manifestUri  The URI for the hook manifest data. 
     */
    function tokenHookManifestUri() external pure returns(string memory manifestUri) {
        manifestUri = ""; //TODO: Before final deploy, create permalink for Standard Hook manifest
    }

    ///////////////////////////////////////////////////////
    //                  VIEW FUNCTIONS                   //
    ///////////////////////////////////////////////////////

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
    ) public view returns (bool pairTokenWhitelisted) {
        pairTokenWhitelisted = _pairTokenWhitelists[pairTokenWhitelistId].contains(pairToken);
    }

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
    ) public view returns (bool lpWhitelisted) {
        lpWhitelisted = _lpWhitelists[lpWhitelistId].contains(account);
    }

    ///////////////////////////////////////////////////////
    //                INTERNAL FUNCTIONS                 //
    ///////////////////////////////////////////////////////

    /**
     * @notice  Checks the hook settings registry for the pool being disabled if the token is set to 
     * @notice  check for disabled pools.
     * 
     * @dev     Throws if the pool is disabled.
     * 
     * @param  tokenSettings The cached settings structure for the token being validated.
     * @param  poolId        ID of the pool to check if it is enabled.
     */
    function _checkPoolEnabled(HookTokenSettings memory tokenSettings, bytes32 poolId) internal view {
        if (tokenSettings.checkDisabledPools) {
            if (SETTINGS_REGISTRY.isPoolDisabled(poolId)) {
                revert AMMStandardHook__PoolDisabled(poolId);
            }
        }
    }

    /**
     * @notice Validates trading status including pause state and if direct swaps are allowed.
     *
     * @dev    Throws if trading is currently paused for the token.
     * @dev    Throws if the trade is a direct swap and direct swaps are not allowed.
     * @dev    Throws if the trade is a direct swap and the paired token is not on the whitelist.
     *
     * @param  tokenSettings The cached settings structure for the token being validated.
     * @param  swapParams    Specific parameters for the swap including amount and direction.
     * @param  pairedToken   The address of the paired token in the swap.
     */
    function _validateTokenTradingRules(
        HookTokenSettings memory tokenSettings,
        HookSwapParams memory swapParams,
        address pairedToken
    ) internal view {
        if (tokenSettings.tradingIsPaused) {
            revert AMMStandardHook__TradingPaused();
        }
        
        if (swapParams.poolId == DIRECT_SWAP_POOL_ID) {
            if (tokenSettings.blockDirectSwaps) {
                revert AMMStandardHook__DirectSwapsNotAllowed();
            }

            // for direct swaps, check if the token settings require a pair token whitelist and if the pairedToken is whitelisted
            if (tokenSettings.pairedTokenWhitelistId > 0) {
                if (!_pairTokenWhitelists[tokenSettings.pairedTokenWhitelistId].contains(pairedToken)) {
                    revert AMMStandardHook__PairNotAllowed();
                }
            }
        }
    }

    /**
     * @notice Calculates the fee based on an amount and a single BPS.
     *
     * @dev    Performs safe mathematical operations to calculate fees without overflow. Returns 0 if
     *         fee rate is 0.
     *
     * @param  amount    The base amount to calculate fees from.
     * @param  feeBPS    The  fee rate in basis points (1 BPS = 0.01%).
     * @return totalFee  The fee amount.
     */
    function _calculateFee(uint256 amount, uint16 feeBPS) internal pure returns (uint256 totalFee) {
        if (feeBPS > 0) {
            totalFee = FullMath.mulDiv(amount, feeBPS, MAX_BPS);
        }
    }

    /**
     * @notice Internal helper to enforce liquidity modification settings for a specific token.
     *
     * @dev    Throws if the provider is not on the required LP whitelist.
     *
     * @dev    Fetches token settings and validates that the liquidity provider is authorized based on
     *         the token's LP whitelist configuration. If no whitelist is configured (ID = 0), all providers are allowed.
     *
     * @param  tokenSettings  The cached settings structure for the token.
     * @param  context        The liquidity context containing the provider address and other details.
     */
    function _enforceLiquidityModificationSettings(HookTokenSettings memory tokenSettings, LiquidityContext calldata context) internal view {
        address provider = context.provider;

        uint256 lpListId = tokenSettings.lpWhitelistId;
        if (lpListId > 0) {
            if (!_lpWhitelists[lpListId].contains(provider)) {
                revert AMMStandardHook__LiquidityProviderNotAllowed();
            }
        }
    }

    /**
     * @notice Internal helper to enforce comprehensive pool creation settings for a specific token's perspective.
     *
     * @dev    Throws if the pool type is not permitted.
     * @dev    Throws if the pool fee is below the minimum required.
     * @dev    Throws if the pool fee exceeds the maximum allowed.
     * @dev    Throws if the pair token is not on the required whitelist.
     * @dev    Throws if the initial price is below the minimum bound.
     * @dev    Throws if the initial price exceeds the maximum bound.
     * @dev    Throws if the creator is not on the required LP whitelist.
     *
     * @dev    Validates all pool creation restrictions including pool type allowances, fee constraints,
     *         pair token whitelist, pricing bounds, and LP whitelist requirements.
     *
     * @param  details        The pool creation details including tokens, fee, type, and initial price.
     * @param  pairedToken    The address of the other token in the pair.
     * @param  creator        The address attempting to create the pool.
     * @param  tokenSettings  The cached settings structure for the token.
     */
    function _enforcePoolCreationSettings(
        bytes32 poolId,
        PoolCreationDetails calldata details,
        address pairedToken,
        address creator,
        HookTokenSettings memory tokenSettings
    ) internal view {
        if (tokenSettings.poolTypeWhitelistId > 0) {
            if (!_poolTypeWhitelists[tokenSettings.poolTypeWhitelistId].contains(details.poolType)) {
                revert AMMStandardHook__PoolTypeNotAllowed();
            }
        }

        if (tokenSettings.minFeeAmount > 0) {
            if (details.fee < tokenSettings.minFeeAmount) {
                revert AMMStandardHook__PoolFeeTooLow();
            }
        }
        if (tokenSettings.maxFeeAmount > 0) {
            if (details.fee > tokenSettings.maxFeeAmount) {
                revert AMMStandardHook__PoolFeeTooHigh();
            }
        }

        if (tokenSettings.pairedTokenWhitelistId > 0) {
            if (!_pairTokenWhitelists[tokenSettings.pairedTokenWhitelistId].contains(pairedToken)) {
                revert AMMStandardHook__PairNotAllowed();
            }
        }

        PricingBounds memory bounds0 = _pricingBounds[details.token0][details.token1];
        PricingBounds memory bounds1 = _pricingBounds[details.token1][details.token0];
        
        if (bounds0.isSet || bounds1.isSet) {
            address poolType = PoolDecoder.getPoolType(poolId);
            uint160 sqrtPriceX96 = ILimitBreakAMMPoolType(poolType).getCurrentPriceX96(AMM, poolId);

            if (bounds0.isSet) {
                if (bounds0.minSqrtPriceX96 != 0 && sqrtPriceX96 < bounds0.minSqrtPriceX96) {
                    revert AMMStandardHook__InvalidPrice();
                }
                if (bounds0.maxSqrtPriceX96 != 0 && sqrtPriceX96 > bounds0.maxSqrtPriceX96) {
                    revert AMMStandardHook__InvalidPrice();
                }
            }

            if (bounds1.isSet) {
                if (bounds1.minSqrtPriceX96 != 0 && sqrtPriceX96 < bounds1.minSqrtPriceX96) {
                    revert AMMStandardHook__InvalidPrice();
                }
                if (bounds1.maxSqrtPriceX96 != 0 && sqrtPriceX96 > bounds1.maxSqrtPriceX96) {
                    revert AMMStandardHook__InvalidPrice();
                }
            }
        }

        _enforceLPWhitelists(creator, tokenSettings);
    }

    /**
     * @notice Internal helper to validate pricing bounds for a swap based on the current price and bounds.
     *
     * @dev    Throws if the current price is below the minimum or above the maximum allowed bounds.
     *            If the swap is in a direction that moves back towards the price limit, it will not revert.
     *
     * @dev    Validates that the current price in the pool is within the specified min/max bounds for the
     *         given token and pair token. If bounds are not set, no validation is performed.
     *
     * @param  params         The hook parameters containing pool ID and swap direction.
     * @param  token          The address of the token being validated.
     * @param  pairedToken    The address of the paired token in the swap.
     * @param  isBeforeSwap   True if the pricing validation is being executed in the beforeSwap hook call, false if in afterSwap.
     */
    function _validatePricingBounds(
        HookSwapParams calldata params,
        address token,
        address pairedToken,
        bool isBeforeSwap
    ) internal {
        PricingBounds memory bounds = _pricingBounds[token][pairedToken];
        if (bounds.isSet) {
            uint160 sqrtPriceX96;

            bool zeroForOne = params.tokenIn < params.tokenOut;
            address poolType = PoolDecoder.getPoolType(params.poolId);
            if (poolType != address(0)) {
                sqrtPriceX96 = ILimitBreakAMMPoolType(poolType).getCurrentPriceX96(AMM, params.poolId);
            } else {
                if (isBeforeSwap) {
                    _setTstorish(DIRECT_SWAP_BEFORE_SWAP_AMOUNT_SLOT, params.amount);
                    return;
                } else {
                    (uint256 amount0, uint256 amount1) = params.inputSwap == zeroForOne ? 
                        (_getTstorish(DIRECT_SWAP_BEFORE_SWAP_AMOUNT_SLOT), params.amount) :
                        (params.amount, _getTstorish(DIRECT_SWAP_BEFORE_SWAP_AMOUNT_SLOT));
                    
                    sqrtPriceX96 = SqrtPriceCalculator.computeRatioX96(amount1, amount0);
                    if (sqrtPriceX96 == 0) {
                        // Price ratio exceeds maximum allowed
                        revert AMMStandardHook__InvalidPrice();
                    }
                }
            }

            if (bounds.minSqrtPriceX96 != 0 && sqrtPriceX96 < bounds.minSqrtPriceX96) {
                // price is below the min price
                // price should be moving down if zeroForOne, so we want to revert
                // for direct swaps where pool type is address(0), always revert
                if (zeroForOne || poolType == address(0)) {
                    revert AMMStandardHook__InvalidPrice();
                }
            }
            if (bounds.maxSqrtPriceX96 != 0 && sqrtPriceX96 > bounds.maxSqrtPriceX96) {
                // price is above the max price
                // price should be moving up if !zeroForOne, so we want to revert
                // for direct swaps where pool type is address(0), always revert
                if (!zeroForOne || poolType == address(0)) {
                    revert AMMStandardHook__InvalidPrice();
                }
            }
        }
    }

    /**
     * @notice Internal helper to enforce LP whitelist restrictions for a given creator and token settings.
     *
     * @dev    Throws if the creator is not on the required LP whitelist.
     *
     * @dev    Validates that the creator is authorized to provide liquidity based on the token's LP whitelist
     *         configuration. If no whitelist is configured (ID = 0), all creators are allowed.
     *
     * @param  creator        The address attempting to create a pool or provide liquidity.
     * @param  tokenSettings  The cached settings structure containing the LP whitelist ID.
     */
    function _enforceLPWhitelists(address creator, HookTokenSettings memory tokenSettings) internal view {
        if (tokenSettings.lpWhitelistId > 0) {
            if (!_lpWhitelists[tokenSettings.lpWhitelistId].contains(creator)) {
                revert AMMStandardHook__LiquidityProviderNotAllowed();
            }
        }
    }

    /**
     * @notice Internal helper to fetch or initialize token settings from cache or registry.
     *
     * @dev    Checks if token settings are already cached and initialized. If not, attempts to fetch from
     *         the registry if the token is initialized there. Otherwise, creates default settings with
     *         no restrictions and caches them.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Token settings have been retrieved from cache or fetched from registry.
     * @dev    2. Settings have been cached locally with the initialized flag set to true.
     * @dev    3. If no registry settings exist, default permissive settings have been created and cached.
     *
     * @param  token           The address of the token to fetch or initialize settings for.
     * @return tokenSettings   The cached or newly fetched settings structure for the token.
     */
    function _getOrFetchTokenSettings(address token) internal returns (HookTokenSettings memory tokenSettings) {
        if (_tokenSettings[token].initialized) {
            tokenSettings = _tokenSettings[token];
        } else {
            if (SETTINGS_REGISTRY.isTokenInitialized(token)) {
                tokenSettings = SETTINGS_REGISTRY.getTokenSettings(token);
                tokenSettings.initialized = true;
                _tokenSettings[token] = tokenSettings;
            } else {
                revert AMMStandardHook__TokenSettingsNotInitialized();
            }
        }
    }

    /**
     * @notice Internal helper to validate that the caller is authorized to modify hook state.
     *
     * @dev    Throws if the caller is not the registry.
     *
     * @dev    Ensures that only the trusted registry contract can call registry
     *         update functions, preventing unauthorized modification of cached data.
     */
    function _requireCallerIsRegistry() internal view {
        if (!(msg.sender == address(SETTINGS_REGISTRY))) {
            revert AMMStandardHook__CallerIsNotRegistry();
        }
    }

    /**
     * @notice Internal helper to validate that the caller is the AMM.
     *
     * @dev    Throws if the caller is not the AMM.
     */
    function _requireCallerIsAMM() internal view {
        if (!(msg.sender == address(AMM))) {
            revert AMMStandardHook__CallerIsNotAMM();
        }
    }

    /**
     * @dev Called internally when tstore is activated by an external call to 
     *      `__activateTstore`. Copies the transient amount value from contract storage 
     *      to transient storage.
     */
    function _onTstoreSupportActivated() internal override {
        assembly("memory-safe") {
            tstore(DIRECT_SWAP_BEFORE_SWAP_AMOUNT_SLOT, sload(DIRECT_SWAP_BEFORE_SWAP_AMOUNT_SLOT))
        }
    }

    ///////////////////////////////////////////////////////
    //               UNUSED HOOK FUNCTIONS               //
    ///////////////////////////////////////////////////////

    /**
     * @notice Collect fees hooks are not supported by this hook.
     */
    function validateCollectFees(
        bool, /*hookForToken0*/
        LiquidityContext calldata, /*context*/
        LiquidityCollectFeesParams calldata, /*liquidityParams*/
        uint256, /*fees0*/
        uint256, /*fees1*/
        bytes calldata /*hookData*/
    ) external pure returns (uint256, uint256) {
        revert AMMStandardHook__HookFunctionNotSupported();
    }

    /**
     * @notice Remove liquidity hooks are not supported by this hook.
     */
    function validateRemoveLiquidity(
        bool, /*hookForToken0*/
        LiquidityContext calldata, /*context*/
        LiquidityModificationParams memory, /*liquidityParams*/
        uint256, /*amount0*/
        uint256, /*amount1*/
        uint256, /*fees0*/
        uint256, /*fees1*/
        bytes calldata /*hookData*/
    ) external pure returns (uint256, uint256) {
        revert AMMStandardHook__HookFunctionNotSupported();
    }
}
