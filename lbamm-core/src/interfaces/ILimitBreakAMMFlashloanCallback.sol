//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../DataTypes.sol";

/**
 * @title  ILimitBreakAMMFlashloanCallback
 * @author Limit Break, Inc.
 * @notice Interface definition for flashloan callback executors to be interacted with from
 *         the core AMM. Flashloan executors will receive the requested flashloan funds from
 *         the AMM along with parameters provided by the requester and information on fees required.
 */
interface ILimitBreakAMMFlashloanCallback {
    /**
     * @notice  Executes a flashloan callback to perform operations with the flashloaned funds.
     * 
     * @dev     Flashloan executor **MUST** return funds directly to the AMM or approve the AMM
     *          to collect funds after the flashloan.
     * 
     * @param requester     Address of the account that requested the flashloan.
     * @param loanToken     Address of the token that was flashloaned.
     * @param loanAmount    Amount of token flashloaned.
     * @param feeToken      Address of the fee token for the flashloan.
     * @param feeAmount     Fee amount in the loan token.
     * @param callbackData  Arbitrary calldata provided by the requester.
     * 
     * @return magicValue   AMM core requires the `magicValue` to return as 
     *                      `ILimitBreakAMMFlashloanCallback.flashloanCallback.selector` to validate 
     *                      executor successfully handled the flashloan execution. 
     */
    function flashloanCallback(
        address requester,
        address loanToken,
        uint256 loanAmount,
        address feeToken,
        uint256 feeAmount,
        bytes calldata callbackData
    ) external returns (bytes4 magicValue);
}