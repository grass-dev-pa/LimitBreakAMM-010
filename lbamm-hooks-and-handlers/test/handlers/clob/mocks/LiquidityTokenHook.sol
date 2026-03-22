pragma solidity 0.8.24;

import "@limitbreak/lb-amm-core/src/Constants.sol";
import "@limitbreak/lb-amm-core/src/DataTypes.sol";
import "@limitbreak/lb-amm-core/src/Errors.sol";

contract LiquidityTokenHook {
    error LiquidityHook__LiquidityAdditionNotAllowed();
    error LiquidityHook__OrderNotAllowed();
    uint256 hookFee0;
    uint256 hookFee1;

    function setHookFees(uint256 hookFee0_, uint256 hookFee1_) external {
        hookFee0 = hookFee0_;
        hookFee1 = hookFee1_;
    }

    function validateAddLiquidity(
        bool /* hookForToken0 */,
        LiquidityContext calldata /* context */,
        LiquidityModificationParams calldata /* liquidityParams */,
        uint256 /* deposit0 */,
        uint256 /* deposit1 */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata hookData
    ) external view returns (uint256, uint256) {
        if (hookData.length > 0) {
            revert LiquidityHook__LiquidityAdditionNotAllowed();
        }

        return (hookFee0, hookFee1);
    }

    function validateHandlerOrder(
        address,
        bool,
        address,
        address,
        uint256,
        uint256,
        bytes calldata,
        bytes calldata hookData
    ) external pure {
        if (hookData.length > 0) {
            revert LiquidityHook__OrderNotAllowed();
        }
    }

    function hookFlags() external pure returns (uint32 required, uint32 supported) {
        return (0, TOKEN_SETTINGS_ADD_LIQUIDITY_HOOK_FLAG | TOKEN_SETTINGS_HANDLER_ORDER_VALIDATE_FLAG);
    }
}
