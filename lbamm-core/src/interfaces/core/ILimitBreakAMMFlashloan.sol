//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "../../DataTypes.sol";

/**
 * @title  ILimitBreakAMMFlashloan
 * @author Limit Break, Inc.
 * @notice Interface definition for AMM core flashloan execution and fee rate functions.
 */
interface ILimitBreakAMMFlashloan {
    /**
     * @notice Returns the current flash loan fee rate.
     *
     * @return flashLoanBPS The flash loan fee rate in basis points.
     */
    function getFlashloanFeeBPS() external view returns (uint16 flashLoanBPS);

    /**
     * @notice Executes a flash loan.
     *
     * @dev    Throws when flash loans are disabled.
     *         Throws when token hook validation fails.
     *         Throws when executor callback fails.
     *         Throws when insufficient tokens returned after callback execution.
     *
     *         Provides temporary access to protocol tokens with deferred payment requirements. Calculates
     *         fees using token hooks or default protocol rates, transfers loan amount to executor,
     *         executes callback function on executor contract, validates return of loan plus fees,
     *         and distributes fees between hook fees and protocol fees.
     *
     *         Supports cross-token fee payments where fees can be paid in a different token than the
     *         loan token, subject to fee token validation hooks. Handles surplus token returns by
     *         adding them to the total fee amount.
     *
     *         <h4>Postconditions:</h4>
     *         1. Loan amount transferred to executor contract
     *         2. Flashloan callback executed on executor with loan details
     *         3. Loan amount plus fees collected from executor
     *         4. Hook fees stored for later distribution to hook contracts
     *         5. Protocol fees stored for later collection
     *         6. Flashloan event emitted with operation details
     *
     * @param flashloanRequest Complete flash loan parameters including loan token, amount, executor address, callback data, and hook validation data.
     */
    function flashLoan(FlashloanRequest calldata flashloanRequest) external;
}
