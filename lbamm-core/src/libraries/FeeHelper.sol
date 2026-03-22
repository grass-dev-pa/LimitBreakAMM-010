//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../Constants.sol";
import "../DataTypes.sol";
import "../Errors.sol";

import "@limitbreak/tm-core-lib/src/utils/math/FullMath.sol";

/**
 * @title  FeeHelper
 * @author Limit Break, Inc.
 * @notice Provides utilities for calculating and applying fees in AMM swap operations.
 * 
 * @dev    This library handles complex fee calculations including exchange fees, fees-on-top, and protocol fees
 *         for both input-based and output-based swap scenarios. It modifies swap cache structures in-place to
 *         track fee amounts and adjust input amounts after fee deductions.
 */
library FeeHelper {

    /**
     * @notice Calculates and applies all fees for input-based swaps, modifying the swap cache in-place.
     *
     * @dev    Throws when fee-on-top amount exceeds the total input amount.
     * @dev    Throws when exchange fee BPS exceeds the maximum allowed fee percentage.
     *
     * @dev    For input-based swaps, fees are deducted from the input amount before the swap calculation.
     *         The function processes fees-on-top first (flat amounts), then exchange fees (percentage-based).
     *         Protocol fees are calculated as a percentage of each fee type and accumulated separately.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. swapCache.amountIn has been reduced by all fee amounts and fees.
     * @dev    2. swapCache.feeOnTopAmount contains the net fee-on-top amount (after protocol fee).
     * @dev    3. swapCache.exchangeFeeAmount contains the net exchange fee amount (after protocol fee).
     * @dev    4. swapCache.protocolFeeFromFees contains the total protocol fee collected from all fees.
     *
     * @param  swapCache              The swap cache structure to modify with calculated fees and adjusted amounts.
     * @param  exchangeFee            Exchange fee configuration with BPS rate and recipient address.
     * @param  feeOnTop               Additional flat fee configuration with amount and recipient address.
     * @param  protocolFeeStructure   Protocol fee configuration containing fee rates for different fee types.
     */
    function calculateAmountAfterFeesSwapByInput(
        InternalSwapCache memory swapCache,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        ProtocolFeeStructure memory protocolFeeStructure
    ) internal pure {
        uint256 amountInAfterFees = swapCache.amountIn;
        uint256 protocolFeesFromSwap;

        uint256 feeOnTopAmount = feeOnTop.amount;
        if (feeOnTopAmount > 0) {
            if (feeOnTopAmount > amountInAfterFees) {
                revert LBAMM__FeeAmountExceedsInputAmount();
            }
            unchecked  {
                amountInAfterFees -= feeOnTopAmount;
            }

            (uint256 feeOnTopAmountToRecipient, uint256 protocolFeeOnTopAmount) = _calculateFlatFeeWithRecipientAndProtocolFee(
                feeOnTopAmount,
                protocolFeeStructure.feeOnTopBPS
            );
            protocolFeesFromSwap = protocolFeeOnTopAmount;
            swapCache.feeOnTopAmount = feeOnTopAmountToRecipient;
        }

        uint256 exchangeFeeBPS = exchangeFee.BPS;
        if (exchangeFeeBPS > 0) {
            (uint256 exchangeFeeAmount, uint256 protocolExchangeFeeAmount) = _calculateBPSFeeWithRecipientAndProtocolFeeSwapByInput(
                exchangeFeeBPS, amountInAfterFees, protocolFeeStructure.exchangeFeeBPS
            );
            protocolFeesFromSwap += protocolExchangeFeeAmount;
            amountInAfterFees -= (exchangeFeeAmount + protocolExchangeFeeAmount);
            swapCache.exchangeFeeAmount = exchangeFeeAmount;
            swapCache.protocolExchangeFeeAmount = protocolExchangeFeeAmount;
        }

        swapCache.amountIn = amountInAfterFees;
        swapCache.protocolFeeFromFees = protocolFeesFromSwap;
    }

    /**
     * @notice Calculates and applies all fees for output-based swaps, modifying the swap cache in-place.
     *
     * @dev    Throws when exchange fee BPS exceeds the maximum allowed fee percentage.
     *
     * @dev    For output-based swaps, fees are added to the required input amount after the swap calculation.
     *         The function processes exchange fees first (percentage-based), then fees-on-top (flat amounts).
     *         Protocol fees are calculated as a percentage of each fee type and accumulated separately.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. swapCache.amountIn has been increased by all fee amounts and fees.
     * @dev    2. swapCache.feeOnTopAmount contains the net fee-on-top amount (after protocol fee).
     * @dev    3. swapCache.exchangeFeeAmount contains the net exchange fee amount (after protocol fee).
     * @dev    4. swapCache.protocolFeeFromFees contains the total protocol fee collected from all fees.
     *
     * @param  swapCache              The swap cache structure to modify with calculated fees and adjusted amounts.
     * @param  feeOnTop               Additional flat fee configuration with amount and recipient address.
     * @param  exchangeFee            Exchange fee configuration with BPS rate and recipient address.
     * @param  protocolFeeStructure   Protocol fee configuration containing fee rates for different fee types.
     */
    function calculateAmountAfterFeesSwapByOutput(
        InternalSwapCache memory swapCache,
        FlatFeeWithRecipient calldata feeOnTop,
        BPSFeeWithRecipient calldata exchangeFee,
        ProtocolFeeStructure memory protocolFeeStructure
    )
        internal
        pure
    {
        uint256 amountIn = swapCache.amountIn;
        uint256 protocolFeesFromSwap = swapCache.protocolFeeFromFees;

        uint256 exchangeFeeBPS = exchangeFee.BPS;
        if (exchangeFeeBPS > 0) {
            (uint256 exchangeFeeAmount, uint256 protocolExchangeFeeAmount) = _calculateBPSFeeWithRecipientAndProtocolFeeSwapByOutput(
                exchangeFeeBPS, amountIn, protocolFeeStructure.exchangeFeeBPS
            );
            protocolFeesFromSwap += protocolExchangeFeeAmount;
            amountIn = amountIn + exchangeFeeAmount + protocolExchangeFeeAmount;
            swapCache.exchangeFeeAmount = exchangeFeeAmount;
        }

        uint256 feeOnTopAmount = feeOnTop.amount;
        if (feeOnTopAmount > 0) {
            amountIn = amountIn + feeOnTopAmount;
            (uint256 feeOnTopAmountToRecipient, uint256 protocolFeeOnTopAmount) =
                _calculateFlatFeeWithRecipientAndProtocolFee(feeOnTopAmount, protocolFeeStructure.feeOnTopBPS);
            protocolFeesFromSwap += protocolFeeOnTopAmount;
            swapCache.feeOnTopAmount = feeOnTopAmountToRecipient;
        }

        swapCache.amountIn = amountIn;
        swapCache.protocolFeeFromFees = protocolFeesFromSwap;
    }

    /**
     * @notice Calculates the fee amount and protocol fee for a flat fee with recipient.
     *
     * @dev    Splits a flat fee amount between the fee recipient and protocol fee based on the fee BPS rate.
     *         The protocol fee is deducted from the total fee amount, with the remainder going to the recipient.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. feeAmount represents the net amount for the fee recipient (after protocol fee).
     * @dev    2. protocolFeeAmount represents the protocol fee portion of the fee.
     * @dev    3. feeAmount + protocolFeeAmount equals the original fee amount.
     *
     * @param  feeOnTopAmount     The flat fee amount for the swap.
     * @param  protocolFeeBPS     The protocol fee rate in basis points applied to the fee.
     * @return feeAmount          The net fee amount for the recipient after protocol fee deduction.
     * @return protocolFeeAmount  The protocol fee amount deducted from the total fee.
     */
    function _calculateFlatFeeWithRecipientAndProtocolFee(uint256 feeOnTopAmount, uint256 protocolFeeBPS)
        internal
        pure
        returns (uint256 feeAmount, uint256 protocolFeeAmount)
    {
        protocolFeeAmount = FullMath.mulDiv(feeOnTopAmount, protocolFeeBPS, MAX_BPS);
        unchecked {
            feeAmount = feeOnTopAmount - protocolFeeAmount;
        }
    }

    /**
     * @notice Calculates the fee amount and protocol fee for a BPS-based fee with recipient when given the input
     *         amount for an input-based swap.
     *
     * @dev    Throws when the fee BPS rate exceeds the maximum allowed fee percentage.
     *
     * @dev    Calculates a percentage-based fee from the swap amount, then splits it between the fee recipient
     *         and protocol fee. The protocol fee is deducted from the calculated fee amount.
     *
     * @param  exchangeFeeBPS     The exchange BPS fee for the swap.
     * @param  inputAmount        The base amount from which to calculate the percentage fee.
     * @param  protocolFeeBPS     The protocol fee rate in basis points applied to the calculated fee.
     * @return feeAmount          The net fee amount for the recipient after protocol fee deduction.
     * @return protocolFeeAmount  The protocol fee amount deducted from the calculated fee.
     */
    function _calculateBPSFeeWithRecipientAndProtocolFeeSwapByInput(
        uint256 exchangeFeeBPS,
        uint256 inputAmount,
        uint256 protocolFeeBPS
    ) internal pure returns (uint256 feeAmount, uint256 protocolFeeAmount) {
        if (exchangeFeeBPS > MAX_BPS) revert LBAMM__FeeAmountExceedsMaxFee();
        feeAmount = FullMath.mulDiv(inputAmount, exchangeFeeBPS, MAX_BPS);
        protocolFeeAmount = FullMath.mulDiv(feeAmount, protocolFeeBPS, MAX_BPS);
        unchecked {
            feeAmount -= protocolFeeAmount;
        }
    }

    /**
     * @notice Calculates the fee amount and protocol fee for a BPS-based fee when given the input amount for
     *         an output-based swap.
     *
     * @dev    Throws when the fee BPS rate exceeds the maximum allowed fee percentage.
     *
     * @dev    For output-based swaps, this function calculates the required fee based on the final input amount
     *         using the formula: fee = input * feeBPS / (MAX_BPS - feeBPS). This ensures the fee is properly
     *         calculated when working backwards from the desired output amount.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. feeAmount represents the net amount for the fee recipient (after protocol fee).
     * @dev    2. protocolFeeAmount represents the protocol fee portion of the calculated fee.
     * @dev    3. The total fee required equals feeAmount + protocolFeeAmount.
     *
     * @param  exchangeFeeBPS     The exchange BPS fee for the swap.
     * @param  inputAmount        The input amount from which to calculate the required fee.
     * @param  protocolFeeBPS     The protocol fee rate in basis points applied to the calculated fee.
     * @return feeAmount          The net fee amount for the recipient after protocol fee deduction.
     * @return protocolFeeAmount  The protocol fee amount deducted from the calculated fee.
     */
    function _calculateBPSFeeWithRecipientAndProtocolFeeSwapByOutput(
        uint256 exchangeFeeBPS,
        uint256 inputAmount,
        uint256 protocolFeeBPS
    ) internal pure returns (uint256 feeAmount, uint256 protocolFeeAmount) {
        if (exchangeFeeBPS >= MAX_BPS) revert LBAMM__FeeAmountExceedsMaxFee();
        unchecked {
            feeAmount = FullMath.mulDivRoundingUp(inputAmount, exchangeFeeBPS, MAX_BPS - exchangeFeeBPS);
            protocolFeeAmount = FullMath.mulDivRoundingUp(feeAmount, protocolFeeBPS, MAX_BPS);
            feeAmount -= protocolFeeAmount;
        }
    }
}
