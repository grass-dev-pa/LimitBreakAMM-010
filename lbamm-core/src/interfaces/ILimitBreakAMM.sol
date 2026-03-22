//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./core/ILimitBreakAMMFees.sol";
import "./core/ILimitBreakAMMFlashloan.sol";
import "./core/ILimitBreakAMMLiquidity.sol";
import "./core/ILimitBreakAMMProtocol.sol";
import "./core/ILimitBreakAMMSwap.sol";
import "./core/ILimitBreakAMMTokenSettings.sol";

/**
 * @title  ILimitBreakAMM
 * @author Limit Break, Inc.
 * @notice Combines the AMM core protocol interfaces into one main interface.
 */
interface ILimitBreakAMM is 
    ILimitBreakAMMFees,
    ILimitBreakAMMFlashloan,
    ILimitBreakAMMLiquidity,
    ILimitBreakAMMProtocol,
    ILimitBreakAMMSwap,
    ILimitBreakAMMTokenSettings {
}
