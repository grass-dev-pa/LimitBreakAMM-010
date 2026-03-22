pragma solidity ^0.8.24;

import "./DynamicPool.t.sol";
import "./mocks/MockHookWithOptimisticFeeCollection.sol";

contract DynamicPoolOptimisticFeeCollectionTest is DynamicPoolTest {
    address currency2Owner;
    address currency3Owner;

    MockHookWithOptimisticFeeCollection optimisticFeeHook;

    function setUp() public virtual override {
        super.setUp();

        optimisticFeeHook = new MockHookWithOptimisticFeeCollection();

        currency2Owner = currency2.owner();
        currency3Owner = currency3.owner();

        changePrank(currency2Owner);
        currency2.transferOwnership(address(909_090_909));
        currency3.transferOwnership(address(909_090_908));

        currency2Owner = address(909_090_909);
        currency3Owner = address(909_090_908);

        changePrank(currency2Owner);
        _setTokenSettings(
            address(currency2),
            address(optimisticFeeHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: true,
                addLiquidityHook: false,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: false,
                hookManagesFees: true,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: false
            }),
            bytes4(0)
        );

        changePrank(currency3Owner);
        _setTokenSettings(
            address(currency3),
            address(optimisticFeeHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: true,
                addLiquidityHook: false,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: false,
                hookManagesFees: true,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: false
            }),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_OptimisticFeeCollection() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        uint256 balance0HookBefore = currency3.balanceOf(address(optimisticFeeHook));

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );

        uint256 balance0HookAfter = currency3.balanceOf(address(optimisticFeeHook));
        uint256 diff0 = balance0HookAfter - balance0HookBefore;
        assertEq(diff0, 100);
    }

    function _calculateHookFeeBeforeSwapSwapByInput(uint256, SwapOrder memory, address)
        internal
        pure
        override
        returns (uint256 hookFee)
    {
        hookFee = 100;
    }

    function _calculateHookFeeBeforeSwapSwapByOutput(uint256, SwapOrder memory, address)
        internal
        pure
        override
        returns (uint256 hookFee)
    {
        hookFee = 100;
    }
}
