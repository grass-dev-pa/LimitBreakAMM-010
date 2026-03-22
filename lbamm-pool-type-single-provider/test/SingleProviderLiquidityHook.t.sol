pragma solidity ^0.8.24;

import "./SingleProviderPool.t.sol";
import {LiquidityLockHook} from "@limitbreak/lb-amm-core/test/mocks/LiquidityLockHook.sol";

contract SingleProviderPoolLiquidityHookTest is SingleProviderPoolTest {
    LiquidityLockHook public liquidityLockHook;

    error LiquidityLockHook__LiquidityRemovalNotAllowed();
    error LiquidityLockHook__FeeCollectionNotAllowed();
    error LiquidityLockHook__LiquidityAdditionNotAllowed();

    function setUp() public override {
        super.setUp();

        liquidityLockHook = new LiquidityLockHook();
    }

    function test_addLiquidityWithPositionHook() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);

        _addSingleProviderLiquidityNoHookData(
            1_000_000,
            1_000_000,
            LiquidityModificationParams({
                liquidityHook: address(liquidityLockHook),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode(SingleProviderLiquidityModificationParams({amount0: 1, amount1: 1}))
            }),
            address(allowedLP),
            bytes4(0)
        );

        _removeSingleProviderLiquidity(
            1_000_000,
            1_000_000,
            LiquidityModificationParams({
                liquidityHook: address(liquidityLockHook),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode("")
            }),
            _emptyLiquidityHooksExtraData(),
            allowedLP,
            bytes4(LiquidityLockHook__LiquidityRemovalNotAllowed.selector)
        );
    }

    function test_collectFeesWithPositionHook() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);

        _addSingleProviderLiquidityNoHookData(
            1_000_000,
            1_000_000,
            LiquidityModificationParams({
                liquidityHook: address(liquidityLockHook),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode(SingleProviderLiquidityModificationParams({amount0: 1, amount1: 1}))
            }),
            address(allowedLP),
            bytes4(0)
        );

        _collectSingleProviderLPFees(
            poolId,
            allowedLP,
            address(liquidityLockHook),
            LiquidityHooksExtraData(bytes(""), bytes(""), bytes("position"), bytes("")),
            bytes4(LiquidityLockHook__FeeCollectionNotAllowed.selector)
        );

        _collectSingleProviderLPFees(
            poolId,
            allowedLP,
            address(liquidityLockHook),
            _emptyLiquidityHooksExtraData(),
            bytes4(0)
        );
    }

    function test_collectFeesWithTokenLiquidityHook() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(liquidityLockHook),
            TokenFlagSettings({
                beforeSwapHook: false,
                afterSwapHook: false,
                addLiquidityHook: false,
                removeLiquidityHook: false,
                collectFeesHook: true,
                poolCreationHook: false,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: false
            }),
            bytes4(0)
        );

        _addSingleProviderLiquidityNoHookData(
            1_000_000,
            1_000_000,
            LiquidityModificationParams({
                liquidityHook: address(0),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode(SingleProviderLiquidityModificationParams({amount0: 1, amount1: 1}))
            }),
            address(allowedLP),
            bytes4(0)
        );

        _collectSingleProviderLPFees(
            poolId,
            allowedLP,
            address(0),
            LiquidityHooksExtraData(bytes("token0"), bytes("token1"), bytes(""), bytes("")),
            bytes4(LiquidityLockHook__FeeCollectionNotAllowed.selector)
        );

        _collectSingleProviderLPFees(
            poolId,
            allowedLP,
            address(0),
            _emptyLiquidityHooksExtraData(),
            bytes4(0)
        );
    }

    function test_addLiquidityWithTokenLiquidityHook() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(liquidityLockHook),
            TokenFlagSettings({
                beforeSwapHook: false,
                afterSwapHook: false,
                addLiquidityHook: true,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: false,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: false
            }),
            bytes4(0)
        );

        _addSingleProviderLiquidity(
            SingleProviderLiquidityModificationParams({amount0: 1000, amount1: 1000}),
            LiquidityModificationParams({
                liquidityHook: address(0),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode("")
            }),
            LiquidityHooksExtraData({
                token0Hook: bytes("token0"),
                token1Hook: bytes("token1"),
                liquidityHook: bytes(""),
                poolHook: bytes("")
            }),
            address(allowedLP),
            bytes4(LiquidityLockHook__LiquidityAdditionNotAllowed.selector)
        );

        _addSingleProviderLiquidity(
            SingleProviderLiquidityModificationParams({amount0: 1000, amount1: 1000}),
            LiquidityModificationParams({
                liquidityHook: address(0),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode("")
            }),
            _emptyLiquidityHooksExtraData(),
            address(allowedLP),
            bytes4(0)
        );
    }

    function test_removeLiquidityWithTokenLiquidityHook() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(liquidityLockHook),
            TokenFlagSettings({
                beforeSwapHook: false,
                afterSwapHook: false,
                addLiquidityHook: false,
                removeLiquidityHook: true,
                collectFeesHook: false,
                poolCreationHook: false,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: false
            }),
            bytes4(0)
        );

        _addSingleProviderLiquidity(
            SingleProviderLiquidityModificationParams({amount0: 1000, amount1: 1000}),
            LiquidityModificationParams({
                liquidityHook: address(0),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode("")
            }),
            _emptyLiquidityHooksExtraData(),
            address(allowedLP),
            bytes4(0)
        );

        _removeSingleProviderLiquidity(
            1000,
            1000,
            LiquidityModificationParams({
                liquidityHook: address(0),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode("")
            }),
            LiquidityHooksExtraData({
                token0Hook: bytes("token0"),
                token1Hook: bytes("token1"),
                liquidityHook: bytes(""),
                poolHook: bytes("")
            }),
            allowedLP,
            bytes4(LiquidityLockHook__LiquidityRemovalNotAllowed.selector)
        );

        _removeSingleProviderLiquidity(
            1000,
            1000,
            LiquidityModificationParams({
                liquidityHook: address(0),
                poolId: poolId,
                minLiquidityAmount0: 0,
                minLiquidityAmount1: 0,
                maxLiquidityAmount0: type(uint256).max,
                maxLiquidityAmount1: type(uint256).max,
                maxHookFee0: type(uint256).max,
                maxHookFee1: type(uint256).max,
                poolParams: abi.encode("")
            }),
            _emptyLiquidityHooksExtraData(),
            allowedLP,
            bytes4(0)
        );
    }
}