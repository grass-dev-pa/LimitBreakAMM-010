//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/**
 * @dev This struct contains the minimum and maximum price bounds for a token pair.
 * 
 * @dev **isSet**: Whether pricing bounds are configured for this token pair.
 * @dev **minSqrtPriceX96**: The minimum allowed square root price in Q96 format.
 * @dev **maxSqrtPriceX96**: The maximum allowed square root price in Q96 format.
 */
struct PricingBounds {
    bool isSet;
    uint160 minSqrtPriceX96;
    uint160 maxSqrtPriceX96;
}

/**
 * @dev This struct contains the comprehensive configuration settings for a token's behavior within the hook system.
 * 
 * @dev **initialized**: Whether the token settings have been initialized in the registry.
 * @dev **tradingIsPaused**: Whether trading is currently paused for this token.
 * @dev **blockDirectSwaps**: True if direct swaps are not allowed for the token.
 * @dev **checkDisabledPools**: True if the hook should check the settings registry for the pool being disabled.
 * @dev **tokenFeeBuyBPS**: The fee in basis points charged on the token when buying.
 * @dev **tokenFeeSellBPS**: The fee in basis points charged on the token when selling.
 * @dev **pairedFeeBuyBPS**: The fee in basis points charged on the paired token when buying.
 * @dev **pairedFeeSellBPS**: The fee in basis points charged on the paired token when selling.
 * @dev **minFeeAmount**: The minimum fee amount that can be set for a pool fee.
 * @dev **maxFeeAmount**: The maximum fee amount that can be set for a pool fee.
 * @dev **poolTypeWhitelistId**: The ID of the whitelist containing allowed pool types (0 = no restrictions).
 * @dev **pairedTokenWhitelistId**: The ID of the whitelist containing allowed pairing tokens (0 = no restrictions).
 * @dev **lpWhitelistId**: The ID of the whitelist containing allowed liquidity providers (0 = no restrictions).
 */
struct HookTokenSettings {
    bool initialized; 
    bool tradingIsPaused;
    bool blockDirectSwaps;
    bool checkDisabledPools;
    uint16 tokenFeeBuyBPS;
    uint16 tokenFeeSellBPS;
    uint16 pairedFeeBuyBPS;
    uint16 pairedFeeSellBPS;
    uint16 minFeeAmount;
    uint16 maxFeeAmount;
    uint56 poolTypeWhitelistId;
    uint56 pairedTokenWhitelistId;
    uint56 lpWhitelistId;
}

/**
 * @dev This struct contains a key-value pair for extensible 32-byte word storage.
 * 
 * @dev **key**: The unique identifier for this expansion data entry.
 * @dev **value**: The 32-byte value associated with the key.
 */
struct ExpansionWord {
    bytes32 key;
    bytes32 value;
}

/**
 * @dev This struct contains a key-value pair for extensible variable-length data storage.
 * 
 * @dev **key**: The unique identifier for this expansion data entry.
 * @dev **value**: The variable-length bytes value associated with the key.
 */
struct ExpansionDatum {
    bytes32 key;
    bytes value;
}