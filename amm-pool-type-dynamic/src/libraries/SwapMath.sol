//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./SqrtPriceMath.sol";
import "../DataTypes.sol";

/**
 * @title  SwapMath
 * @notice Contains methods for computing the result of a swap within a single tick price range in concentrated liquidity pools.
 * @dev    This library provides the core mathematical functions for executing swap steps in dynamic pools. It handles
 *         both input-based and output-based swaps, computing token amounts, price movements, and fees within individual
 *         tick ranges. The calculations account for current price, target price, available liquidity, and pool fees.
 */
library SwapMath {
    /**
     * @notice Computes a single swap step for input-based swaps within a tick range.
     *
     * @dev    This function calculates how much of the input amount can be consumed within the current tick range,
     *         determines the resulting price movement, and computes the corresponding output amount and fees.
     *         For input-based swaps, the input amount is known and the output amount is calculated.
     *
     * @dev    The function handles two scenarios:
     *         1. The entire remaining input can be consumed within this tick range
     *         2. Only part of the input is consumed, reaching the tick boundary
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. swapCache.sqrtPriceCurrentX96 has been updated to the new price after the swap step.
     * @dev    2. step.amountIn has been set to the input amount consumed in this step.
     * @dev    3. step.amountOut has been set to the output amount produced in this step.
     * @dev    4. step.feeAmount has been set to the fee amount collected in this step.
     *
     * @param  swapCache    Cache containing swap state including current price, liquidity, and remaining amounts.
     * @param  step         Step computation structure to store calculated amounts and updated price.
     * @param  poolFeeBPS   The pool's fee rate in basis points.
     */
    function computeSwapByInputStep(
        DynamicSwapCache memory swapCache,
        StepComputations memory step,
        uint24 poolFeeBPS
    ) internal pure {
        unchecked {
            uint160 sqrtPriceTargetX96 = step.sqrtPriceNextX96;
            uint160 sqrtPriceNextX96;
            uint256 amountIn;
            uint256 amountOut;
            uint256 feeAmount;

            bool zeroForOne = swapCache.zeroForOne;
            uint128 liquidity = swapCache.liquidity;
            uint160 sqrtPriceCurrentX96 = swapCache.sqrtPriceCurrentX96;
            uint256 amountRemaining = swapCache.amountSpecifiedRemaining;

            uint256 amountRemainingLessFee =
                FullMath.mulDiv(amountRemaining, MAX_BPS - poolFeeBPS, MAX_BPS);
            amountIn = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, true);
            if (amountRemainingLessFee >= amountIn) {
                // `amountIn` is capped by the target price
                sqrtPriceNextX96 = sqrtPriceTargetX96;

                // input-based swap may have a fee of 10,000 BPS (100%)
                feeAmount = poolFeeBPS == MAX_BPS
                    ? amountIn // amountIn is always 0 here, as amountRemainingLessFee == 0 and amountRemainingLessFee >= amountIn
                    : FullMath.mulDivRoundingUp(amountIn, poolFeeBPS, MAX_BPS - poolFeeBPS);
            } else {
                // exhaust the remaining amount
                amountIn = amountRemainingLessFee;
                sqrtPriceNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtPriceCurrentX96, liquidity, amountRemainingLessFee, zeroForOne
                );
                // we didn't reach the target, so take the remainder of the maximum input as fee
                feeAmount = amountRemaining - amountIn;
            }
            amountOut = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, false)
                : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);

            swapCache.sqrtPriceCurrentX96 = sqrtPriceNextX96;
            step.amountIn = amountIn;
            step.amountOut = amountOut;
            step.feeAmount = feeAmount;
        }
    }

    /**
     * @notice Computes a single swap step for output-based swaps within a tick range.
     *
     * @dev    This function calculates how much input is required to produce the desired output amount within
     *         the current tick range, determines the resulting price movement, and computes the corresponding
     *         fees. For output-based swaps, the output amount is known and the input amount is calculated.
     *
     * @dev    The function handles two scenarios:
     *         1. The entire remaining output can be produced within this tick range
     *         2. Only part of the output is produced, reaching the tick boundary
     *
     * @dev    The output amount is capped to not exceed the remaining output amount requested.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. swapCache.sqrtPriceCurrentX96 has been updated to the new price after the swap step.
     * @dev    2. step.amountIn has been set to the input amount required for this step.
     * @dev    3. step.amountOut has been set to the output amount produced in this step (capped to remaining).
     * @dev    4. step.feeAmount has been set to the fee amount collected in this step.
     *
     * @param  swapCache    Cache containing swap state including current price, liquidity, and remaining amounts.
     * @param  step         Step computation structure to store calculated amounts and updated price.
     * @param  poolFeeBPS   The pool's fee rate in basis points.
     */
    function computeSwapByOutputStep(
        DynamicSwapCache memory swapCache,
        StepComputations memory step,
        uint24 poolFeeBPS
    ) internal pure {
        unchecked {
            uint160 sqrtPriceTargetX96 = step.sqrtPriceNextX96;
            uint160 sqrtPriceNextX96;
            uint256 amountIn;
            uint256 amountOut;
            uint256 feeAmount;

            bool zeroForOne = swapCache.zeroForOne;
            uint128 liquidity = swapCache.liquidity;
            uint160 sqrtPriceCurrentX96 = swapCache.sqrtPriceCurrentX96;
            uint256 amountRemaining = swapCache.amountSpecifiedRemaining;

            amountOut = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, false)
                : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, false);
            if (uint256(amountRemaining) >= amountOut) {
                // `amountOut` is capped by the target price
                sqrtPriceNextX96 = sqrtPriceTargetX96;
            } else {
                // cap the output amount to not exceed the remaining output amount
                amountOut = uint256(amountRemaining);
                sqrtPriceNextX96 =
                    SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtPriceCurrentX96, liquidity, amountOut, zeroForOne);
            }
            amountIn = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);
            
            // output-based swap fee cannot exceed 9,999 BPS (99.99%)
            feeAmount = FullMath.mulDivRoundingUp(amountIn, poolFeeBPS, MAX_BPS - poolFeeBPS);

            swapCache.sqrtPriceCurrentX96 = sqrtPriceNextX96;
            step.amountIn = amountIn;
            step.amountOut = amountOut;
            step.feeAmount = feeAmount;
        }
    }
}