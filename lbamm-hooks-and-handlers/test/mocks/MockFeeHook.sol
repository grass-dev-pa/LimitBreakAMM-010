pragma solidity 0.8.24;

import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMM.sol";
import "@limitbreak/lb-amm-core/src/interfaces/hooks/ILimitBreakAMMTokenHook.sol";

contract MockHookWithFees {
    /// @notice Flags of hook functions that this contract supports (optional implementations)
    uint32 private constant _supportedHookFlags = 1 << 0 | 1 << 1;

    /// @notice Flags of hook functions that this contract requires (mandatory implementations)
    uint32 private constant _requiredHookFlags = 0;

    function beforeSwap(SwapContext calldata /* context */, HookSwapParams calldata /* swapParams */, bytes calldata /*hookData*/ )
        external pure
        returns (uint256 fee)
    {
        fee = 100;
    }

    function afterSwap(SwapContext calldata /* context */, HookSwapParams calldata /* swapParams */, bytes calldata /*hookData*/ )
        external pure
        returns (uint256 fee)
    {
        fee = 100;
    }

    function hookFlags() external pure returns (uint32 requiredFlags, uint32 supportedFlags) {
        return (_requiredHookFlags, _supportedHookFlags);
    }
}
