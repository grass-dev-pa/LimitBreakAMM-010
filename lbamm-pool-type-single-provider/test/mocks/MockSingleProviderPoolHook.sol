pragma solidity ^0.8.24;

import "../../src/interfaces/ISingleProviderPoolHook.sol";

contract MockSingleProviderPoolHook is ISingleProviderPoolHook {
    function validatePoolCreation(bytes32, address, PoolCreationDetails calldata, bytes calldata) external pure override {}

    function getPoolFeeForSwap(SwapContext calldata, HookPoolFeeParams calldata, bytes calldata hookData)
        external
        pure
        override
        returns (uint256)
    {
        return abi.decode(hookData, (uint256));
    }

    function validatePoolCollectFees(
        LiquidityContext calldata,
        LiquidityCollectFeesParams calldata,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (uint256, uint256) {}

    function validatePoolAddLiquidity(
        LiquidityContext calldata,
        LiquidityModificationParams calldata,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (uint256, uint256) {}

    function validatePoolRemoveLiquidity(
        LiquidityContext calldata,
        LiquidityModificationParams calldata,
        uint256,
        uint256,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (uint256, uint256) {}

    function getPoolPriceForSwap(SwapContext calldata, HookPoolPriceParams calldata, bytes calldata)
        external
        pure
        override
        returns (uint160)
    {
        return 79_228_162_514_264_337_593_543_950_336;
    }

    function getPoolLiquidityProvider(bytes32 /* poolId */) external pure override returns (address) {
        return address(8_675_309);
    }

    function poolHookManifestUri() external pure returns(string memory manifestUri) { manifestUri = ""; }
}