//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

/**
 * @dev Internal data structure used to store the input/output tokens and amounts.
 * 
 * @dev **tokenIn**:    The input token from the context of the CLOB.
 * @dev **tokenOut**:   The output token from the context of the CLOB.
 * @dev **amountIn**:   The amount in from the context of the CLOB.
 * @dev **amountOut**:  The amount out from the context of the CLOB.
 */
struct FillCache {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 amountOut;
}

/**
 * @dev Key containing pertinent information that establishes a unique order book.
 *
 * @dev **tokenIn**:           The address of the input token for the order book.
 * @dev **tokenOut**:          The address of the output token for the order book.
 * @dev **hook**:              The address of a CLOB hook that can be used to modify the behavior of the order book.  
 * @dev **minimumOrderBase**:  The base amount of the minimum order size.
 * @dev **minimumOrderScale**: The scale of the minimum order size.
 *         E.g. if the base is 10 and scale is 18, the minimum order size would be 10 * 10^18.
 */
struct OrderBookKey {
    address tokenIn;
    address tokenOut;
    address hook;
    uint16 minimumOrderBase;
    uint8 minimumOrderScale;
}

/**
 * @dev Struct representing a specific order book.
 * @dev **currentPrice**:     The current price of the order book.
 * @dev **nextPriceAbove**:   A mapping of prices in ascending order.
 * @dev **nextPriceBelow**:   A mapping of prices in descending order.
 * @dev **priceOrderBucket**: A mapping containing the order buckets for each price.
 */
struct OrderBook {
    uint160 currentPrice;
    mapping (uint160 => uint160) nextPriceAbove;
    mapping (uint160 => uint160) nextPriceBelow;
    mapping (uint160 => OrderBucket) priceOrderBucket;
}

/**
 * @dev Struct representing an order bucket with in an order book at a specific price.
 * @dev **currentOrderId**:       The ID of the current order in the bucket.
 * @dev **inputAmountRemaining**: The remaining input amount for the current order.
 * @dev **nextOrder**:            A mapping of order IDs to the next order ID in the bucket.
 * @dev **previousOrder**:        A mapping of order IDs to the previous order ID in the bucket.
 * @dev **orders**:               A mapping of order nonce to the Order struct.
 */
struct OrderBucket {
    bytes32 currentOrderId;
    uint256 inputAmountRemaining;
    mapping (bytes32 => bytes32) nextOrder;
    mapping (bytes32 => bytes32) previousOrder;
    mapping (uint256 => Order) orders;
}

/**
 * @dev Struct representing an order opened by a maker.
 * @dev **maker**:       The address of the maker who opened the order.
 * @dev **orderNonce**:  The nonce of the order
 * @dev **inputAmount**: The total amount of the input token for the order.
 */
struct Order {
    address maker;
    uint256 orderNonce;
    uint256 inputAmount;
}

/**
 * @dev Struct representing the parameters for filling an order.
 * @dev **groupKey**:          The order book hook, minimumOrderBase, minimumOrderScale hashed together.
 * @dev **maxOutputSlippage**: The maximum slippage allowed for the output token. 
 * @dev **hookData**:          Arbitrary calldata to be passed to the validation hook.
 */
struct FillParams {
    bytes32 groupKey;
    uint256 maxOutputSlippage;
    bytes hookData;
}

/**
 * @dev Struct for the hook extra data that is provided with an order opening.
 * @dev **tokenInHook**:   Calldata to be passed to the input token add liquidity hook.
 * @dev **tokenOutHook**:  Calldata to be passed to the output token add liquidity hook.
 * @dev **clobHook**:      Calldata to be passed to the CLOB group's validation hook.
 */
struct HooksExtraData {
    bytes tokenInHook;
    bytes tokenOutHook;
    bytes clobHook;
}