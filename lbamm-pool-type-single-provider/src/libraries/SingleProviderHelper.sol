//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../Constants.sol";
import "../DataTypes.sol";
import "../Errors.sol";

import "@limitbreak/tm-core-lib/src/utils/math/FullMath.sol";

/**
 * @title  SingleProviderHelper
 * @author Limit Break, Inc.
 * @notice Provides utilities for single-provider fixed pools in the Limit Break AMM.
 *
 * @dev    Contains swap logic, fee calculations, and fixed-point math for single-provider pool types.
 */
library SingleProviderHelper {

    /**
     * @notice Executes a fixed input swap for a single-provider pool.
     *
     * @dev    Throws when output amount exceeds available reserves.
     *
     *         Calculates output using fixed-point math, applies LP and protocol fees, and updates swap cache.
     *
     * @param  swapCache     Swap operation context and state (input/output, price, direction, reserves, fees).
     * @param  poolFeeBPS    Pool LP fee rate in basis points.
     */
    function swapByInput(
        SingleProviderSwapCache memory swapCache,
        uint16 poolFeeBPS
    ) internal pure {
        (
            uint256 amountInAfterFees,
            uint256 lpFeeAmount,
            uint256 protocolFeeAmount
        ) = _calculateInputLPAndProtocolFee(swapCache.amountIn, poolFeeBPS, swapCache.protocolFeeBPS);

        uint160 sqrtPriceX96 = swapCache.sqrtPriceCurrentX96;
        bool zeroForOne = swapCache.zeroForOne;
        
        uint256 amountOut = swapCache.amountOut = calculateFixedInput(amountInAfterFees, sqrtPriceX96, zeroForOne);
        if (amountOut > swapCache.reserveOut) {
            //attempt an output-based swap for remaining reserves
            swapCache.amountOut = swapCache.reserveOut;
            uint256 initialAmountIn = swapCache.amountIn;
            swapByOutput(swapCache, poolFeeBPS);

            if (swapCache.amountIn > initialAmountIn) {
                revert SingleProviderPool__ActualAmountCannotExceedInitialAmount(); 
            }
        } else {
            swapCache.feeAmount = lpFeeAmount;
            swapCache.protocolFee = protocolFeeAmount;
        }
    }


    /**
     * @dev    Calculates LP and protocol fees for an input-based swap.
     *
     * @param  amountIn            Input amount before fees.
     * @param  poolFeeBPS          Pool LP fee rate in basis points.
     * @param  lpFeeBPS            Protocol fee rate in basis points.
     * @return amountInAfterFees   Input amount after all fees.
     * @return lpFeeAmount         Fee amount allocated to liquidity providers.
     * @return protocolFeeAmount   Fee amount allocated to protocol.
     */
    function _calculateInputLPAndProtocolFee(
        uint256 amountIn,
        uint16 poolFeeBPS,
        uint16 lpFeeBPS
    ) internal pure returns (
        uint256 amountInAfterFees,
        uint256 lpFeeAmount,
        uint256 protocolFeeAmount
    ) {
        lpFeeAmount = FullMath.mulDivRoundingUp(amountIn, poolFeeBPS, MAX_BPS);
        unchecked {
            amountInAfterFees = amountIn - lpFeeAmount;
        }
        if (lpFeeBPS > 0) {
            protocolFeeAmount = FullMath.mulDiv(lpFeeAmount, lpFeeBPS, MAX_BPS);
            unchecked {
                lpFeeAmount -= protocolFeeAmount;
            }
        }
    }

    /**
     * @notice Calculates output amount for an input-based swap using the single provider pool price.
     *
     * @dev    Uses fixed-point arithmetic for conservative output calculation. Direction determines
     *         whether to multiply or divide by price.
     *
     * @param  amountIn     Input amount for the swap.
     * @param  sqrtPriceX96 Pool's sqrt price in Q96 format.
     * @param  zeroForOne   True if swapping token0 for token1, false otherwise.
     * @return amountOut    Calculated output amount from the swap.
     */
    function calculateFixedInput(
        uint256 amountIn,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) internal pure returns (uint256 amountOut) {
        if (zeroForOne) {
            amountOut = FullMath.mulDiv(amountIn, sqrtPriceX96, Q96);
            amountOut = FullMath.mulDiv(amountOut, sqrtPriceX96, Q96);
        } else {
            amountOut = FullMath.mulDiv(amountIn, Q96, sqrtPriceX96);
            amountOut = FullMath.mulDiv(amountOut, Q96, sqrtPriceX96);
        }
    }

    /**
     * @notice Executes a fixed output swap for a single-provider pool.
     *
     * @dev    Throws when output amount exceeds available reserves.
     *
     *         Calculates required input using fixed-point math, applies LP and protocol fees, and updates swap cache.
     *
     * @param  swapCache     Swap operation context and state (input/output, price, direction, reserves, fees).
     * @param  poolFeeBPS    Pool LP fee rate in basis points.
     */
    function swapByOutput(
        SingleProviderSwapCache memory swapCache,
        uint16 poolFeeBPS
    ) internal pure {
        uint256 amountOut = swapCache.amountOut;
        if (amountOut > swapCache.reserveOut) {
            amountOut = swapCache.amountOut = swapCache.reserveOut;
        }

        uint160 sqrtPriceX96 = swapCache.sqrtPriceCurrentX96;
        bool zeroForOne = swapCache.zeroForOne;

        uint256 reserveAmountIn = calculateFixedOutput(amountOut, sqrtPriceX96, zeroForOne);

        (
            uint256 swapAmountIn,
            uint256 lpFeeAmount,
            uint256 protocolFeeAmount
        ) = _calculateOutputLPAndProtocolFee(reserveAmountIn, poolFeeBPS, swapCache.protocolFeeBPS);

        swapCache.amountIn = swapAmountIn;
        swapCache.feeAmount = lpFeeAmount;
        swapCache.protocolFee = protocolFeeAmount;
    }

    /**
     * @dev    Calculates LP and protocol fees for an output-based swap.
     *
     * @param  reserveAmountIn     Reserve input amount before fees.
     * @param  poolFeeBPS          Pool LP fee rate in basis points.
     * @param  lpFeeBPS            Protocol fee rate in basis points.
     * @return amountInAfterFees   Input amount after all fees.
     * @return lpFeeAmount         Fee amount allocated to liquidity providers.
     * @return protocolFeeAmount   Fee amount allocated to protocol.
     */
    function _calculateOutputLPAndProtocolFee(
        uint256 reserveAmountIn,
        uint16 poolFeeBPS,
        uint16 lpFeeBPS
    ) internal pure returns (
        uint256 amountInAfterFees,
        uint256 lpFeeAmount,
        uint256 protocolFeeAmount
    ) {
        lpFeeAmount = FullMath.mulDivRoundingUp(reserveAmountIn, poolFeeBPS, MAX_BPS - poolFeeBPS);
        unchecked {
            amountInAfterFees = reserveAmountIn + lpFeeAmount;
        }
        if (lpFeeBPS > 0) {
            protocolFeeAmount = FullMath.mulDiv(lpFeeAmount, lpFeeBPS, MAX_BPS);
            unchecked {
                lpFeeAmount -= protocolFeeAmount;
            }
        }
    }

    /**
     * @notice Calculates required input amount for an output-based swap using fixed pool price.
     *
     * @dev    Uses fixed-point arithmetic to compute input needed for desired output. Direction determines whether to 
     *         multiply or divide by price.
     *
     * @param  amountOut    Desired output amount.
     * @param  sqrtPriceX96 Pool's sqrt price in Q96 format.
     * @param  zeroForOne   True if swapping token0 for token1, false otherwise.
     * @return amountIn     Required input amount for the swap.
     */
    function calculateFixedOutput(
        uint256 amountOut,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) internal pure returns (uint256 amountIn) {
        if (zeroForOne) {
            amountIn = FullMath.mulDivRoundingUp(amountOut, Q96, sqrtPriceX96);
            amountIn = FullMath.mulDivRoundingUp(amountIn, Q96, sqrtPriceX96);
        } else {
            amountIn = FullMath.mulDivRoundingUp(amountOut, sqrtPriceX96, Q96);
            amountIn = FullMath.mulDivRoundingUp(amountIn, sqrtPriceX96, Q96);
        }
    }
}
