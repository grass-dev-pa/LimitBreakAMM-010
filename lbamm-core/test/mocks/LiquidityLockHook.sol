pragma solidity 0.8.24;

import "../../src/interfaces/hooks/ILimitBreakAMMLiquidityHook.sol";
import "../../src/DataTypes.sol";
import "../../src/Errors.sol";


contract LiquidityLockHook is ILimitBreakAMMLiquidityHook {
    error LiquidityLockHook__LiquidityRemovalNotAllowed();
    error LiquidityLockHook__FeeCollectionNotAllowed();
    error LiquidityLockHook__LiquidityAdditionNotAllowed();

    function validatePositionAddLiquidity(
        LiquidityContext calldata /* context */,
        LiquidityModificationParams calldata /* liquidityParams */,
        uint256 /* deposit0 */,
        uint256 /* deposit1 */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata hookData
    ) external pure override returns (uint256, uint256) {
        if (hookData.length > 0) {
            revert LiquidityLockHook__LiquidityAdditionNotAllowed();
        }
    }

    function validatePositionRemoveLiquidity(
        LiquidityContext calldata /* context */,
        LiquidityModificationParams calldata /* liquidityParams */,
        uint256 /* withdraw0 */,
        uint256 /* withdraw1 */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata /* hookData */
    ) external pure override returns (uint256, uint256) {
        revert LiquidityLockHook__LiquidityRemovalNotAllowed();
    }

    function validatePositionCollectFees(
        LiquidityContext calldata /* context */,
        LiquidityCollectFeesParams calldata /* liquidityParams */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata hookData
    ) external pure returns (uint256, uint256) {
        if (hookData.length > 0) {
            revert LiquidityLockHook__FeeCollectionNotAllowed();
        } 
    }

    function validateCollectFees(
        bool /* hookForToken0 */,
        LiquidityContext calldata /* context */,
        LiquidityCollectFeesParams calldata /* liquidityParams */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata hookData
    ) external pure returns (uint256, uint256) {
        if (hookData.length > 0) {
            revert LiquidityLockHook__FeeCollectionNotAllowed();
        } 
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
    ) external pure returns (uint256, uint256) { 
        if (hookData.length > 0) {
            revert LiquidityLockHook__LiquidityAdditionNotAllowed();
        }
    }

    function validateRemoveLiquidity(
        bool /* hookForToken0 */,
        LiquidityContext calldata /* context */,
        LiquidityModificationParams calldata /* liquidityParams */,
        uint256 /* withdraw0 */,
        uint256 /* withdraw1 */,
        uint256 /* fees0 */,
        uint256 /* fees1 */,
        bytes calldata hookData
    ) external pure returns (uint256, uint256) {
        if (hookData.length > 0) {
            revert LiquidityLockHook__LiquidityRemovalNotAllowed();
        }
    }

    function hookFlags() external pure returns (uint32 required, uint32 supported) {
        return (0, 1 << 2 | 1 << 3 | 1 << 4 );
    }

    function liquidityHookManifestUri() external pure returns(string memory manifestUri) { manifestUri = ""; }
}