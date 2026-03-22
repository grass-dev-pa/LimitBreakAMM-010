pragma solidity 0.8.24;

import "src/interfaces/hooks/ILimitBreakAMMPoolHook.sol";

contract MockPoolHook is ILimitBreakAMMPoolHook {
    function getPoolFeeForSwap(SwapContext calldata /* context */, HookPoolFeeParams calldata /* poolFeeParams */, bytes calldata /* hookData */)
        external
        pure
        override
        returns (uint256 poolFeeBPS)
    {
        poolFeeBPS = 5000;
    }

    function validatePoolRemoveLiquidity(
        LiquidityContext calldata /* context */,
        LiquidityModificationParams calldata /* liquidityParams */,
        uint256 /* withdraw0 */,
        uint256 /* withdraw1 */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata /* hookData */
    ) external pure override returns (uint256, uint256) {
        //
    }

    function validatePoolAddLiquidity(
        LiquidityContext calldata /* context */,
        LiquidityModificationParams calldata /* liquidityParams */,
        uint256 /* deposit0 */,
        uint256 /* deposit1 */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata /* hookData */
    ) external pure override returns (uint256, uint256){
        //
    }

    function validatePoolCollectFees(
        LiquidityContext calldata /* context */,
        LiquidityCollectFeesParams calldata /* liquidityParams */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata /* hookData */
    ) external pure returns (uint256, uint256) {

    }

    function validatePoolCreation(bytes32 /*poolId*/, address /* creator */, PoolCreationDetails calldata /* details */, bytes calldata /* hookData */)
        external
        pure
        override
    {
        //
    }

    function poolHookManifestUri() external pure returns(string memory manifestUri) { manifestUri = ""; }
}