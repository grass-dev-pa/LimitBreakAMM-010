pragma solidity ^0.8.24;

import "../DynamicPool.t.sol";

contract DynamicPoolFuzzTest is DynamicPoolTest {

    function setUp() public override {
        super.setUp();
    }

    function test_fuzz_addDynamicLiquidity(int24 tickLower, int24 tickUpper, uint256 liquidityChange) public {
        bytes32 poolId = _createStandardDynamicPool();

        tickLower = int24(bound(tickLower, MIN_TICK, MAX_TICK));
        tickUpper = int24(bound(tickUpper, MIN_TICK, MAX_TICK));

        vm.assume(tickLower % 10 == 0 && tickUpper % 10 == 0);
        vm.assume(tickLower < tickUpper);
        vm.assume(tickLower != 0 && tickUpper != 0);
        liquidityChange = bound(liquidityChange, 1, _poolMaxLiquidityPerTick(poolId));

        _mintAndApprove(address(usdc), alice, address(amm), type(uint128).max);
        _mintAndApprove(address(weth), alice, address(amm), type(uint128).max);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityChange: int128(int256(liquidityChange)),
            snapSqrtPriceX96: 0
        });


            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));
    }

    function test_fuzz_removeDynamicLiquidity(int24 tickLower, int24 tickUpper, uint256 liquidityChange) public {
        bytes32 poolId = _createStandardDynamicPool();

        tickLower = int24(bound(tickLower, MIN_TICK, MAX_TICK));
        tickUpper = int24(bound(tickUpper, MIN_TICK, MAX_TICK));

        vm.assume(tickLower % 10 == 0 && tickUpper % 10 == 0);
        vm.assume(tickLower < tickUpper);
        vm.assume(tickLower != 0 && tickUpper != 0);
        liquidityChange = bound(liquidityChange, 1, _poolMaxLiquidityPerTick(poolId));

        _mintAndApprove(address(usdc), alice, address(amm), type(uint128).max);
        _mintAndApprove(address(weth), alice, address(amm), type(uint128).max);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityChange: int128(uint128(liquidityChange)),
            snapSqrtPriceX96: 0
        });

        
            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        bytes32 positionId = EfficientHash.efficientHash(
            EfficientHash.efficientHash(
                bytes32(uint256(uint160(alice))), bytes32(uint256(uint160(address(0)))), liquidityParams.poolId
            ),
            bytes32(uint256(uint24(dynamicParams.tickLower))),
            bytes32(uint256(uint24(dynamicParams.tickUpper)))
        );

        DynamicPositionInfo memory position = dynamicPool.getPositionInfo(address(amm), positionId);

        _removeDynamicLiquidity(
            DynamicLiquidityModificationParams({
                tickLower: dynamicParams.tickLower,
                tickUpper: dynamicParams.tickUpper,
                liquidityChange: -int128(position.liquidity),
                snapSqrtPriceX96: 0
            }),
            liquidityParams,
            _emptyLiquidityHooksExtraData(),
            alice,
            bytes4(0)
        );
    }

    function test_fuzz_singleSwap_verifyInputAndOutputBasedFeesIdentical(uint256 amountSpecified) public {
        amountSpecified = bound(amountSpecified, 1000, 1_000_000e6);
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({recipient: address(bob), BPS: 100});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({recipient: address(bob), amount: 10});

        uint256 snapshot = vm.snapshotState();

        SwapOrder memory swapOrder =
            _createSwapOrder(alice, int256(amountSpecified), 0, address(usdc), address(weth), block.timestamp + 1);

        SwapHooksExtraData memory swapHooksExtraData;
        bytes memory transferData = bytes("");

        changePrank(swapOrder.recipient);
        (uint256 amountInDeltaSwapByIn, uint256 amountOutDeltaSwapByIn) = _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        vm.revertToState(snapshot);

        swapOrder.amountSpecified = -int256(amountOutDeltaSwapByIn);
        swapOrder.limitAmount = type(uint256).max;

        changePrank(swapOrder.recipient);
        (uint256 amountInDeltaSwapByOut, uint256 amountOutDeltaSwapByOut) = _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        assertApproxEqAbs(
            amountInDeltaSwapByIn, amountInDeltaSwapByOut, 1, "DynamicPool: Amount in deltas should be equal"
        );
        assertApproxEqAbs(
            amountOutDeltaSwapByIn, amountOutDeltaSwapByOut, 1, "DynamicPool: Amount out deltas should be equal"
        );
    }

    function test_fuzz_lpFeeAllocation(uint256 numOfDepositors) public {
        numOfDepositors = bound(numOfDepositors, 2, 100);
        // give me an array of addresses with numOfDepositors elements
        address[] memory depositors = new address[](numOfDepositors);
        uint256[] memory userLiquidity = new uint256[](numOfDepositors);
        uint256[] memory amount0Collected = new uint256[](numOfDepositors);
        uint256[] memory amount1Collected = new uint256[](numOfDepositors);

        bytes32 poolId = _createStandardDynamicPool();

        int24 tickLower;
        int24 tickUpper;

        {
            DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

            tickLower = poolState.tick - (10 * _getPoolTickSpacing(poolId));
            tickLower = _roundToTickSpacing(tickLower, _getPoolTickSpacing(poolId));
            tickUpper = poolState.tick + (10 * _getPoolTickSpacing(poolId));
            tickUpper = _roundToTickSpacing(tickUpper, _getPoolTickSpacing(poolId));
        }

        for (uint256 i = 0; i < numOfDepositors; i++) {
            address depositor = address(uint160(uint256(keccak256(abi.encodePacked(i)))));
            uint256 amount = bound(uint256(keccak256(abi.encodePacked(i))), 10 ether, 100 ether);

            depositors[i] = depositor;

            console2.log("Depositor:", depositor);
            console2.log("Amount %d:", amount);

            uint256 deposit0;
            uint256 deposit1;
            {
                LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

                DynamicLiquidityModificationParams memory dynamicParams =
                    _initDynamicLiqParams(tickLower, tickUpper, int128(uint128(amount)));

                _mintAndApprove(address(usdc), depositor, address(amm), 100_000 ether);
                _mintAndApprove(address(weth), depositor, address(amm), 100_000 ether);
                (deposit0, deposit1,,) =
                    _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, depositor, bytes4(0));
            }

            bytes32 positionId = EfficientHash.efficientHash(
                EfficientHash.efficientHash(
                    bytes32(uint256(uint160(depositor))), bytes32(uint256(uint160(address(0)))), poolId
                ),
                bytes32(uint256(uint24(tickLower))),
                bytes32(uint256(uint24(tickUpper)))
            );
            {
                DynamicPositionInfo memory positionInfo = dynamicPool.getPositionInfo(address(amm), positionId);

                userLiquidity[i] = positionInfo.liquidity;
            }
        }

        DynamicPoolState memory state = dynamicPool.getPoolState(address(amm), poolId);
        uint256 feeAmount;
        {
            int256 amountSpecified = 1_000_000;
            _mintAndApprove(address(usdc), alice, address(amm), 10 ether);
            SwapOrder memory swapOrder =
                _createSwapOrder(alice, amountSpecified, 0, address(usdc), address(weth), block.timestamp + 1);

            (uint256 amountInDelta, ) = _executeDynamicPoolSingleSwap(
                swapOrder,
                poolId,
                BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
                FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
                _emptySwapHooksExtraData(),
                bytes(""),
                bytes4(0)
            );
            feeAmount = FullMath.mulDiv(amountInDelta, 500, 10_000);
            feeAmount -= amm.getProtocolFees(address(usdc));
        }

        uint256 totalFeesCollected;

        for (uint256 i = 0; i < numOfDepositors; i++) {
            (amount0Collected[i], amount1Collected[i]) =
                _collectDynamicPoolLPFees(poolId, tickLower, tickUpper, depositors[i], bytes4(0));
            totalFeesCollected += amount0Collected[i];

            uint256 expectedFees = FullMath.mulDiv(feeAmount, userLiquidity[i], state.liquidity);

            assertEq(amount0Collected[i], expectedFees, "Fees collected by depositor should match expected fees");
        }

        assertApproxEqAbs(feeAmount, totalFeesCollected, numOfDepositors);
    }
}
