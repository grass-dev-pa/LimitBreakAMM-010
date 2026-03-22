//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../Constants.sol";
import "../DataTypes.sol";
import "../Errors.sol";

import "@limitbreak/tm-core-lib/src/utils/math/FullMath.sol";

/**
 * @title  CLOBHelper
 * @author Limit Break, Inc.
 * @notice Provides utilities for opening, closing and filling CLOB orders.
 *
 * @dev    This library contains the core logic for CLOB management including order modifications and filling.
 */
library CLOBHelper {

    /**
     * @notice  Closes a maker's order within an order book. 
     * 
     * @param ptrOrderBook          Storage pointer to the order book the order is being closed on.
     * @param maker                 Address of the order maker.
     * @param sqrtPriceX96          Price that the order was placed at.
     * @param orderNonce            Nonce assigned to the order at its creation.
     * @return unfilledInputAmount  Amount of input that was not filled.
     */
    function closeOrder(
        OrderBook storage ptrOrderBook,
        address maker,
        uint160 sqrtPriceX96,
        uint256 orderNonce
    ) internal returns (uint256 unfilledInputAmount) {
        OrderBucket storage ptrOrderBucket = ptrOrderBook.priceOrderBucket[sqrtPriceX96];
        Order storage ptrOrder = ptrOrderBucket.orders[orderNonce];
        if (ptrOrder.maker != maker) {
            revert CLOBTransferHandler__InvalidMaker();
        }
        if (ptrOrder.inputAmount == 0) {
            revert CLOBTransferHandler__OrderInvalidFilledOrClosed();
        }

        bytes32 orderId = _orderToOrderId(ptrOrder);
        bytes32 currentOrderId = ptrOrderBucket.currentOrderId;

        if (orderId == currentOrderId) {
            unchecked {
                unfilledInputAmount = ptrOrderBucket.inputAmountRemaining;

                (,,uint256 updatedInputAmountRemaining, uint160 nextSqrtPriceX96) = traverseCLOB(
                    ptrOrderBook,
                    ptrOrderBucket,
                    sqrtPriceX96,
                    currentOrderId,
                    false
                );

                if (nextSqrtPriceX96 == sqrtPriceX96) {
                    // Next order is within the same bucket, update amount remaining
                    ptrOrderBucket.inputAmountRemaining = updatedInputAmountRemaining;
                }
            }
        } else {
            Order storage ptrCurrentOrder = _orderIdToOrder(currentOrderId);
            if (ptrOrder.orderNonce > ptrCurrentOrder.orderNonce) {
                unfilledInputAmount = ptrOrder.inputAmount;

                bytes32 previousOrder = ptrOrderBucket.previousOrder[orderId];
                bytes32 nextOrder = ptrOrderBucket.nextOrder[orderId];
                ptrOrderBucket.nextOrder[previousOrder] = nextOrder;
                ptrOrderBucket.previousOrder[nextOrder] = previousOrder;
            } else {
                revert CLOBTransferHandler__OrderInvalidFilledOrClosed();
            }
        }

        ptrOrder.inputAmount = 0;
    }

    /**
     * @notice  Opens an order for the maker in the order book.
     * 
     * @param ptrOrderBook      Storage pointer to the order book the order is being opened on.
     * @param orderNonce        Nonce assigned to the order.
     * @param maker             Address of the order maker.
     * @param sqrtPriceX96      Price to place the order at.
     * @param orderAmount       Amount of input token for the order.
     * @param hintSqrtPriceX96  Hint for finding the location to insert the order in the linked lists.
     */
    function openOrder(
        OrderBook storage ptrOrderBook,
        uint256 orderNonce,
        address maker,
        uint160 sqrtPriceX96,
        uint256 orderAmount,
        uint160 hintSqrtPriceX96
    ) internal {
        if (orderAmount == 0) {
            revert CLOBTransferHandler__ZeroOrderAmount();
        }

        if (orderAmount > type(uint128).max) {
            revert CLOBTransferHandler__OrderAmountExceedsMax();
        }

        if (sqrtPriceX96 < MIN_SQRT_RATIO || sqrtPriceX96 > MAX_SQRT_RATIO) {
            revert CLOBTransferHandler__InvalidSqrtPriceX96();
        }

        uint160 currentPrice = ptrOrderBook.currentPrice;
        if (currentPrice == 0) {
            ptrOrderBook.currentPrice = sqrtPriceX96;
            ptrOrderBook.nextPriceAbove[0] = sqrtPriceX96;
            ptrOrderBook.nextPriceBelow[sqrtPriceX96] = 0;
            ptrOrderBook.nextPriceAbove[sqrtPriceX96] = type(uint160).max;
            ptrOrderBook.nextPriceBelow[type(uint160).max] = sqrtPriceX96;
        } else {
            if (sqrtPriceX96 < currentPrice) {
                ptrOrderBook.currentPrice = sqrtPriceX96;
            }

            if (ptrOrderBook.nextPriceAbove[sqrtPriceX96] == 0) {
                uint160 nextPriceAbove;
                uint160 nextPriceBelow;
                while (true) {
                    nextPriceAbove = ptrOrderBook.nextPriceAbove[hintSqrtPriceX96];
                    if (nextPriceAbove > sqrtPriceX96) {
                        nextPriceBelow = ptrOrderBook.nextPriceBelow[nextPriceAbove];
                        if (nextPriceBelow < sqrtPriceX96) {
                            break;
                        } else {
                            hintSqrtPriceX96 = ptrOrderBook.nextPriceBelow[nextPriceBelow];
                            continue;
                        }
                    } else {
                        hintSqrtPriceX96 = nextPriceAbove;
                        continue;
                    }
                }
                ptrOrderBook.nextPriceAbove[nextPriceBelow] = sqrtPriceX96;
                ptrOrderBook.nextPriceBelow[nextPriceAbove] = sqrtPriceX96;
                ptrOrderBook.nextPriceAbove[sqrtPriceX96] = nextPriceAbove;
                ptrOrderBook.nextPriceBelow[sqrtPriceX96] = nextPriceBelow;
            }
        }

        OrderBucket storage ptrOrderBucket = ptrOrderBook.priceOrderBucket[sqrtPriceX96];
        Order storage ptrOrder = ptrOrderBucket.orders[orderNonce];
        ptrOrder.maker = maker;
        ptrOrder.orderNonce = orderNonce;
        ptrOrder.inputAmount = orderAmount;

        bytes32 thisOrderId = _orderToOrderId(ptrOrder);
        bytes32 currentOrderId = ptrOrderBucket.currentOrderId;
        bytes32 lastOrderId = ptrOrderBucket.previousOrder[bytes32(0)];
        ptrOrderBucket.previousOrder[bytes32(0)] = thisOrderId;
        ptrOrderBucket.nextOrder[lastOrderId] = thisOrderId;
        ptrOrderBucket.previousOrder[thisOrderId] = lastOrderId;

        if (currentOrderId == bytes32(0)) {
            ptrOrderBucket.inputAmountRemaining = orderAmount;
            ptrOrderBucket.currentOrderId = thisOrderId;
        }
    }
    
    /**
     * @notice  Fills orders in the order book until the input amount is fully consumed.
     * 
     * @dev     The entire output amount may not be consumed through order filling and should be credited to executor.
     * 
     * @param ptrOrderBook       Storage pointer to the order book the order is being filled on.
     * @param makerTokenBalance  Storage pointer to the mapping of maker token balance of the output token.
     * @param inputAmount        Amount of input to consume in the order book.
     * @param outputAmount       Amount of output supplied by the fill order.
     * 
     * @return fillOutputRemaining        Amount of output remaining after filling the input.
     * @return endingOrderNonce           Nonce of the new head order for the order book.
     * @return endingOrderInputRemaining  Amount of input remaining on the new head order in the order book.
     */
    function fillOrder(
        OrderBook storage ptrOrderBook,
        mapping (address maker => uint256 balance) storage makerTokenBalance,
        uint256 inputAmount,
        uint256 outputAmount
    ) internal returns (uint256 fillOutputRemaining, uint256 endingOrderNonce, uint256 endingOrderInputRemaining) {
        uint160 currentPrice = ptrOrderBook.currentPrice;

        if (currentPrice == 0 || currentPrice == type(uint160).max) {
            revert CLOBTransferHandler__InvalidPrice();
        }

        OrderBucket storage ptrOrderBucket = ptrOrderBook.priceOrderBucket[currentPrice];
        Order storage ptrOrder = _orderIdToOrder(ptrOrderBucket.currentOrderId);
        
        fillOutputRemaining = outputAmount;
        uint256 fillInputRemaining = inputAmount;
        uint256 orderInputRemaining = ptrOrderBucket.inputAmountRemaining;
        address maker;
        uint256 stepOutput;
        uint256 stepInput;
        while (fillInputRemaining != 0) {
            maker = ptrOrder.maker;

            stepInput = orderInputRemaining;
            unchecked {
                if (stepInput > fillInputRemaining) {
                    stepInput = fillInputRemaining;
                    orderInputRemaining = orderInputRemaining - stepInput;
                    fillInputRemaining = 0;
                    stepOutput = calculateFixedInput(stepInput, currentPrice);
                } else {
                    fillInputRemaining = fillInputRemaining - stepInput;
                    stepOutput = calculateFixedInput(stepInput, currentPrice);

                    // Order has filled, close order by setting input amount to zero
                    ptrOrder.inputAmount = 0;

                    (ptrOrderBucket, ptrOrder, orderInputRemaining, currentPrice) = traverseCLOB(ptrOrderBook, ptrOrderBucket, currentPrice, _orderToOrderId(ptrOrder), true);

                    if (orderInputRemaining == 0) {
                        if (fillInputRemaining != 0) {
                            revert CLOBTransferHandler__InsufficientInputToFill();
                        }
                    }
                }
            }

            if (stepOutput > fillOutputRemaining) {
                revert CLOBTransferHandler__InsufficientOutputToFill();
            }
            unchecked {
                fillOutputRemaining = fillOutputRemaining - stepOutput;
            }
            makerTokenBalance[maker] += stepOutput;
        }

        endingOrderNonce = ptrOrder.orderNonce;
        ptrOrderBucket.inputAmountRemaining = endingOrderInputRemaining = orderInputRemaining;
    }

    /**
     * @notice  Traverse the CLOB when an order has been filled or closed to queue the next order to fill.
     * 
     * @param ptrOrderBook            Storage pointer to the order book.
     * @param ptrOrderBucket          Storage pointer to the bucket within the order book.
     * @param sqrtPriceX96            Current price in the order book.
     * @param currentOrderId          Current active order id in the order book.
     * @param orderFill               True if the traversal originates from filling the current order.
     * 
     * @return ptrUpdatedOrderBucket  Updated storage pointer for the order bucket, if changed by traversal.
     * @return ptrUpdatedOrder        Storage pointer for the new active order after traversal.
     * @return inputAmountRemaining   Amount of input remaining for the new active order.
     * @return nextSqrtPriceX96       Updated price for the order book, if changed by traversal.
     */
    function traverseCLOB(
        OrderBook storage ptrOrderBook,
        OrderBucket storage ptrOrderBucket,
        uint160 sqrtPriceX96,
        bytes32 currentOrderId,
        bool orderFill
    ) internal returns (
        OrderBucket storage ptrUpdatedOrderBucket,
        Order storage ptrUpdatedOrder,
        uint256 inputAmountRemaining,
        uint160 nextSqrtPriceX96
    ) {
        bytes32 nextOrderId = ptrOrderBucket.nextOrder[currentOrderId];
        ptrOrderBucket.currentOrderId = nextOrderId;

        // Clean order pointers
        ptrOrderBucket.nextOrder[currentOrderId] = bytes32(0);
        ptrOrderBucket.previousOrder[nextOrderId] = bytes32(0);

        if (nextOrderId == bytes32(0)) {
            nextSqrtPriceX96 = ptrOrderBook.nextPriceAbove[sqrtPriceX96];
            uint160 prevSqrtPriceX96 = ptrOrderBook.nextPriceBelow[sqrtPriceX96];
            ptrOrderBook.nextPriceBelow[nextSqrtPriceX96] = prevSqrtPriceX96;
            ptrOrderBook.nextPriceAbove[prevSqrtPriceX96] = nextSqrtPriceX96;
            ptrOrderBook.nextPriceAbove[sqrtPriceX96] = 0;
            ptrOrderBook.nextPriceBelow[sqrtPriceX96] = 0;
            ptrOrderBucket.inputAmountRemaining = 0;

            // Move order book current price if filling orders or closing an order that is the current price
            if (orderFill || ptrOrderBook.currentPrice == sqrtPriceX96) {
                ptrOrderBook.currentPrice = nextSqrtPriceX96;
            }

            ptrUpdatedOrderBucket = ptrOrderBook.priceOrderBucket[nextSqrtPriceX96];
            ptrUpdatedOrder = _orderIdToOrder(ptrUpdatedOrderBucket.currentOrderId);
            inputAmountRemaining = ptrUpdatedOrderBucket.inputAmountRemaining;
        } else {
            ptrUpdatedOrderBucket = ptrOrderBucket;
            ptrUpdatedOrder = _orderIdToOrder(nextOrderId);
            inputAmountRemaining = ptrUpdatedOrder.inputAmount;
            nextSqrtPriceX96 = sqrtPriceX96;
        }
    }

    /**
     * @notice Calculates output amount for an input-based swap using the order price.
     *
     * @dev    Uses fixed-point arithmetic with rounding up for conservative output calculation.
     *
     * @param  amountIn     Input amount for the swap.
     * @param  sqrtPriceX96 Pool's sqrt price in Q96 format.
     * 
     * @return amountOut    Calculated output amount from the swap.
     */
    function calculateFixedInput(
        uint256 amountIn,
        uint160 sqrtPriceX96
    ) internal pure returns (uint256 amountOut) {
        amountOut = FullMath.mulDivRoundingUp(amountIn, sqrtPriceX96, Q96);
        amountOut = FullMath.mulDivRoundingUp(amountOut, sqrtPriceX96, Q96);
    }

    /**
     * @notice  Converts a storage pointer to its slot address to use as an identifier for linking orders.
     * 
     * @param ptrOrder  Storage pointer for the order to convert to orderId.
     * 
     * @return orderId  The storage slot of the order, used as an identifier.
     */
    function _orderToOrderId(Order storage ptrOrder) internal pure returns (bytes32 orderId) {
        assembly ("memory-safe") {
            orderId := ptrOrder.slot
        }
    }

    /**
     * @notice  Converts an orderId to the Order storage pointer.
     * 
     * @param orderId  The storage slot of the order.
     * 
     * @return ptrOrder  Storage pointer for the order.
     */
    function _orderIdToOrder(bytes32 orderId) internal pure returns (Order storage ptrOrder) {
        assembly ("memory-safe") {
            ptrOrder.slot := orderId
        }
    }
}