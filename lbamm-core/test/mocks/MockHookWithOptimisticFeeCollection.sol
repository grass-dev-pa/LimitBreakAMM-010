pragma solidity 0.8.24;

import "src/Constants.sol";

import "src/interfaces/ILimitBreakAMM.sol";
import "src/interfaces/hooks/ILimitBreakAMMTokenHook.sol";

contract MockHookWithOptimisticFeeCollection {
    /// @notice Flags of hook functions that this contract supports (optional implementations)
    uint32 private constant _supportedHookFlags = TOKEN_SETTINGS_BEFORE_SWAP_HOOK_FLAG
        | TOKEN_SETTINGS_AFTER_SWAP_HOOK_FLAG | TOKEN_SETTINGS_HOOK_MANAGES_FEES_FLAG;

    /// @notice Flags of hook functions that this contract requires (mandatory implementations)
    uint32 private constant _requiredHookFlags = TOKEN_SETTINGS_BEFORE_SWAP_HOOK_FLAG
        | TOKEN_SETTINGS_AFTER_SWAP_HOOK_FLAG | TOKEN_SETTINGS_HOOK_MANAGES_FEES_FLAG;

    function beforeSwap(SwapContext calldata /* context */, HookSwapParams calldata /* swapParams */, bytes calldata /*hookData*/ )
        external pure
        returns (uint256 fee)
    {
        fee = 100;
    }

    function afterSwap(SwapContext calldata /* context */, HookSwapParams calldata swapParams, bytes calldata /*hookData*/ )
        external
        returns (uint256 fee)
    {
        fee = 0;
        if (swapParams.inputSwap && swapParams.hookForInputToken) {
            uint256 amount =
                ILimitBreakAMM(msg.sender).getHookFeesOwedByHook(address(this), swapParams.tokenIn, swapParams.tokenIn);
            ILimitBreakAMM(msg.sender).collectHookFeesByHook(
                swapParams.tokenIn, swapParams.tokenIn, address(this), amount
            );
        } else if (!swapParams.inputSwap && !swapParams.hookForInputToken) {
            uint256 amount = ILimitBreakAMM(msg.sender).getHookFeesOwedByHook(
                address(this), swapParams.tokenOut, swapParams.tokenOut
            );
            ILimitBreakAMM(msg.sender).collectHookFeesByHook(
                swapParams.tokenOut, swapParams.tokenOut, address(this), amount
            );
        }
    }

    function hookFlags() external pure returns (uint32 requiredFlags, uint32 supportedFlags) {
        return (_requiredHookFlags, _supportedHookFlags);
    }
}
