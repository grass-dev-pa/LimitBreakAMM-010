pragma solidity 0.8.24;

import "@limitbreak/lb-amm-core/src/Constants.sol";
import "@limitbreak/lb-amm-core/src/interfaces/hooks/ILimitBreakAMMLiquidityHook.sol";

contract MockLiquidityHookAudit is ILimitBreakAMMLiquidityHook {
    uint256 public stateOnlyToBeUpdatedIfCalledByToken;
    uint256 public stateOnlyToBeUpdatedIfCalledByPool;
    uint256 public stateOnlyToBeUpdatedIfCalledByPosition;

    /*function getFixedPoolPriceForSwap(SwapContext calldata context, HookPoolPriceParams calldata poolPriceParams, bytes calldata hookData)
        external
        view
        override
        returns (uint256 poolPrice)
    {
        poolPrice = 1;
    }

    function getFixedPoolDynamicPriceProvider(
        bytes32 poolId
    ) external view returns (address provider) {
        provider = address(0);
    }*/

    function validatePositionRemoveLiquidity(
        LiquidityContext calldata,
        LiquidityModificationParams calldata,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external override returns (uint256, uint256) {
        stateOnlyToBeUpdatedIfCalledByPosition++;
    }

    function validatePositionAddLiquidity(
        LiquidityContext calldata,
        LiquidityModificationParams calldata,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external override returns (uint256, uint256) {
        stateOnlyToBeUpdatedIfCalledByPosition++;
    }

    function validatePositionCollectFees(
        LiquidityContext calldata,
        LiquidityCollectFeesParams calldata,
        uint256,
        uint256,
        bytes calldata
    ) external returns (uint256, uint256) {}

    function validateAddLiquidity(
        bool,
        LiquidityContext calldata,
        LiquidityModificationParams calldata,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external returns (uint256, uint256) {
        stateOnlyToBeUpdatedIfCalledByToken++;
    }

    function validatePoolCreation(address, PoolCreationDetails calldata, bytes calldata) external {}

    function validatePoolAddLiquidity(
        LiquidityContext calldata,
        LiquidityModificationParams calldata,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external returns (uint256, uint256) {
        stateOnlyToBeUpdatedIfCalledByPool++;
    }

    function hookFlags() external pure returns (uint32 requiredFlags, uint32 supportedFlags) {
        supportedFlags = TOKEN_SETTINGS_BEFORE_SWAP_HOOK_FLAG | TOKEN_SETTINGS_AFTER_SWAP_HOOK_FLAG
            | TOKEN_SETTINGS_ADD_LIQUIDITY_HOOK_FLAG | TOKEN_SETTINGS_REMOVE_LIQUIDITY_HOOK_FLAG;
        requiredFlags = 0;
    }

    function liquidityHookManifestUri() external pure returns(string memory manifestUri) { manifestUri = ""; }
}
