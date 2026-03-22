pragma solidity ^0.8.24;

import "@limitbreak/lb-amm-core/test/LBAMMCorePoolBase.t.sol";

import "../src/DataTypes.sol";

import {PoolDecoder} from "@limitbreak/lb-amm-core/src/libraries/PoolDecoder.sol";

import {SingleProviderPoolType} from "../src/SingleProviderPoolType.sol";
import "../src/interfaces/ISingleProviderPoolHook.sol";
import {MockSingleProviderPoolHook} from "./mocks/MockSingleProviderPoolHook.sol";

contract SingleProviderPoolTest is LBAMMCorePoolBaseTest {
    SingleProviderPoolType internal singleProviderPool;
    MockSingleProviderPoolHook internal spPoolHook;

    address allowedLP;

    error SingleProviderPool__NoPoolHookProvided();
    error SingleProviderPool__NotAllowedProvider();
    error SingleProviderPool__InsufficientReserves();
    error SingleProviderPool__OnlyAMM();

    function setUp() public virtual override {
        super.setUp();

        allowedLP = address(8_675_309);

        singleProviderPool = new SingleProviderPoolType(address(amm));
        vm.etch(address(9090), address(singleProviderPool).code);
        singleProviderPool = SingleProviderPoolType(address(9090));

        spPoolHook = new MockSingleProviderPoolHook();
        vm.etch(address(6060), address(spPoolHook).code);
        spPoolHook = MockSingleProviderPoolHook(address(6060));

        vm.label(address(singleProviderPool), "Single Provider Pool");
        vm.label(address(spPoolHook), "Single Provider Pool Hook");
    }

    function test_dynamicFeeHook() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(currency3),
            token1: address(currency2),
            fee: 55_555, // This is the fee flag for Dynamic Pool Fee
            poolType: address(singleProviderPool),
            poolHook: address(spPoolHook),
            poolParams: bytes("")
        });

        bytes32 salt = keccak256(abi.encode("single-provider-test"));

        bytes32 poolId = _createSingleProviderPoolNoHookData(details, salt, bytes4(0));

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency3), alice, address(amm), 1 ether);

        // Test Hook Directly //
        bytes memory hookData = abi.encode(9999);

        uint256 poolFee = spPoolHook.getPoolFeeForSwap(
            SwapContext(address(0), address(0), address(0), 0, address(0), 0, address(0), address(0), address(0), 1),
            HookPoolFeeParams(true, 0, bytes32("nothinghere"), address(0), address(0), 0),
            hookData
        );

        assertEq(poolFee, 9999, "Pool fee should match the hook data");

        // Test With Swap //

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = SwapHooksExtraData({
            tokenInHook: bytes(""),
            tokenOutHook: bytes(""),
            poolHook: hookData,
            poolType: bytes("")
        });

        bytes memory transferData = bytes("");

        (uint256 amountIn, uint256 amountOut) = _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        assertEq(amountIn, uint256(swapOrder.amountSpecified), "AmountIn Incorrect");
        assertEq(amountOut, uint256(swapOrder.amountSpecified) - (uint256(swapOrder.amountSpecified) * 9999 / 10_000));
    }

    function test_createSingleProviderPool() external {
        bytes32 poolId = _createStandardSingleProviderPool();

        PoolState memory state = amm.getPoolState(poolId);

        assertEq(state.token0, address(currency3), "Token0 mismatch");
        assertEq(state.token1, address(currency2), "Token1 mismatch");
        assertEq(state.poolHook, address(spPoolHook), "PoolHook mismatch");

        bytes32 computedPoolId = singleProviderPool.computePoolId(
            PoolCreationDetails({
                token0: address(currency3),
                token1: address(currency2),
                fee: 500,
                poolType: address(singleProviderPool),
                poolHook: address(spPoolHook),
                poolParams: abi.encode(
                    SingleProviderPoolCreationDetails({salt: keccak256(abi.encode("single-provider-test")), sqrtPriceRatioX96: 2**96})
                )
            })
        );

        assertEq(poolId, computedPoolId, "Pool ID mismatch");
    }

    function test_addLiquidity() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);
    }

    function test_addLiquidity_revert_NotAllowedProvider() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _addSingleProviderLiquidityNoHookData(
            1,
            1,
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
            address(999_999),
            bytes4(SingleProviderPool__NotAllowedProvider.selector)
        );
    }

    function test_removeLiquidity() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _removeSingleProviderLiquidity(
            100_000 ether,
            100_000 ether,
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

    function test_removeLiquidity_revert_NotAllowedProvider() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _removeSingleProviderLiquidity(
            1,
            1,
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
            address(999_999),
            bytes4(SingleProviderPool__NotAllowedProvider.selector)
        );
    }

    function test_removeLiquidity_revert_InsufficientReserves() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _removeSingleProviderLiquidity(
            100_000 ether + 1,
            10_000 ether + 1,
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
            bytes4(SingleProviderPool__InsufficientReserves.selector)
        );
    }

    function test_singleSwapByInputZeroForOne() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency3), alice, address(amm), 1 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );
    }

    function test_singleSwapByOutputZeroForOne() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency3), alice, address(amm), 10 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );
    }

    function test_singleSwapByInputOneForZero() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency2), alice, address(amm), 10 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency2),
            tokenOut: address(currency3)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );
    }

    function test_singleSwapByOutputOneForZero() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency2), alice, address(amm), 10 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency2),
            tokenOut: address(currency3)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );
    }

    function test_singleSwapByInputZeroForOne_PartialFill() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency3), alice, address(amm), 100_000_000 ether);

        PoolState memory poolState = LimitBreakAMM(amm).getPoolState(poolId);
        uint256 reserves1 = poolState.reserve1;

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: int256(reserves1 * 1055 / 1000), // Requesting 105% of reserves
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        (uint256 amountIn,) = _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        assertLt(amountIn, uint256(swapOrder.amountSpecified), "AmountIn should be less than amountSpecified");
    }

    function test_singleSwapByOutputZeroForOne_PartialFill() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency3), alice, address(amm), 100_000_000 ether);

        PoolState memory poolState = LimitBreakAMM(amm).getPoolState(poolId);
        uint256 reserves0 = poolState.reserve0;

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: -int256(reserves0 * 1055 / 1000),
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        (,uint256 amountOut) = _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );
        assertLt(amountOut, uint256(-swapOrder.amountSpecified), "AmountOut should be less than amountSpecified");
    }

    function test_singleSwap_PartialFill_compareInputAndOutputBased() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency3), alice, address(amm), 100_000_000 ether);

        PoolState memory poolState = LimitBreakAMM(amm).getPoolState(poolId);
        uint256 reserves1 = poolState.reserve1;

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: int256(reserves1 * 1055 / 1000), // Requesting 105% of reserves
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        uint256 snapshot = vm.snapshotState();

        (uint256 amountInSwapByIn, uint256 amountOutSwapByIn) = _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        vm.revertToState(snapshot);

        swapOrder.amountSpecified = -int256(swapOrder.amountSpecified);
        swapOrder.limitAmount = type(uint256).max;

        (uint256 amountInSwapByOut, uint256 amountOutSwapByOut) = _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        assertEq(amountOutSwapByIn, amountOutSwapByOut, "Amount out deltas should be equal");
        assertEq(amountInSwapByIn, amountInSwapByOut, "Amount in deltas should be equal");
    }

    function test_singleSwapByInputOneForZeroCollectProtocolFees() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency2), alice, address(amm), 10 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency2),
            tokenOut: address(currency3)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        address[] memory tokens = new address[](2);
        tokens[0] = address(currency2);
        tokens[1] = address(currency3);

        _collectProtocolFees(tokens, bytes4(0));
    }

    function test_singleSwapHookDataVariousLengths() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency2), alice, address(amm), 10 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency2),
            tokenOut: address(currency3)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = SwapHooksExtraData({
            tokenInHook: bytes("1"),
            tokenOutHook: bytes("11"),
            poolHook: bytes("111"),
            poolType: bytes("")
        });

        bytes memory transferData = bytes("");

        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        swapHooksExtraData.tokenInHook = bytes("1111");
        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        swapHooksExtraData.tokenOutHook = bytes("11111");
        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );
    }

    function test_SingleSwapByInputLPFeeOverride() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        changePrank(AMM_ADMIN);
        _setLPProtocolFeeOverride(poolId, true, 10_000, bytes4(0));

        _mintAndApprove(address(currency3), alice, address(amm), 1 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        (uint256 collected0, uint256 collected1) = _collectSingleProviderLPFees(poolId, allowedLP, bytes4(0));
        assertEq(collected0, 0, "Collected fees should be 0");
        assertEq(collected1, 0, "Collected fees should be 0");
        uint256 protocolFees0 = amm.getProtocolFees(address(currency2));
        uint256 protocolFees1 = amm.getProtocolFees(address(currency3));
        assertEq(protocolFees0, 0, "Protocol fees for token0 should be 0");
        assertEq(
            protocolFees1,
            FullMath.mulDiv(1 ether, 500, 10_000),
            "Protocol fees for token1 should be 500 bps of 1 ether"
        );
    }

    function test_SingleSwapByInputFeeOnTopOverride() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        changePrank(AMM_ADMIN);
        _setFeeOnTopProtocolFeeOverride(feeOnTopRecipient, true, 10_000, bytes4(0));

        _mintAndApprove(address(currency3), alice, address(amm), 1 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0.1 ether, recipient: feeOnTopRecipient});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        (uint256 amountIn,) = _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        uint256 expectedProtocolFee;
        {
            uint256 amountInMinusFeeOnTop = amountIn - feeOnTop.amount;
            expectedProtocolFee = FullMath.mulDiv(amountInMinusFeeOnTop, 500, 10_000);
            expectedProtocolFee = FullMath.mulDiv(expectedProtocolFee, 125, 10_000);
            expectedProtocolFee += feeOnTop.amount; // Add the fee on top to the protocol fee
        }

        uint256 protocolFees0 = amm.getProtocolFees(address(currency2));
        uint256 protocolFees1 = amm.getProtocolFees(address(currency3));
        assertEq(protocolFees0, 0, "Protocol fees for token0 should be 0");
        assertEq(protocolFees1, expectedProtocolFee, "Protocol fees for token1 should be 0.1 ether");
    }

    function test_SingleSwapByInputExchangeFeeOverride() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);

        changePrank(AMM_ADMIN);
        _setExchangeProtocolFeeOverride(exchangeFeeRecipient, true, 10_000, bytes4(0));

        _mintAndApprove(address(currency3), alice, address(amm), 1 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 500, recipient: exchangeFeeRecipient});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        (uint256 amountIn,) = _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        uint256 expectedProtocolFee;
        {
            uint256 exchangeFeeAmount = FullMath.mulDiv(amountIn, exchangeFee.BPS, 10_000);
            uint256 amountInMinusExchangeFee = amountIn - exchangeFeeAmount;
            expectedProtocolFee = FullMath.mulDiv(amountInMinusExchangeFee, 500, 10_000);
            expectedProtocolFee = FullMath.mulDiv(expectedProtocolFee, 125, 10_000);
            expectedProtocolFee += exchangeFeeAmount;
        }

        uint256 protocolFees0 = amm.getProtocolFees(address(currency2));
        uint256 protocolFees1 = amm.getProtocolFees(address(currency3));
        assertEq(protocolFees0, 0, "Protocol fees for token0 should be 0");
        assertEq(protocolFees1, expectedProtocolFee, "Protocol fees for token1 should be 0.1 ether");
    }

    function test_createPool_revert_DirectCallNotAMM() public {
        PoolCreationDetails memory poolCreationDetails = PoolCreationDetails({
            token0: address(currency3),
            token1: address(currency2),
            fee: 500,
            poolType: address(singleProviderPool),
            poolHook: address(spPoolHook),
            poolParams: bytes("")
        });

        vm.expectRevert(SingleProviderPool__OnlyAMM.selector);
        singleProviderPool.createPool(poolCreationDetails);
    }

    function test_getCurrentPriceX96() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        {
            _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
            _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
            _addStandardSingleProviderLiquidity(poolId);

            _mintAndApprove(address(currency3), alice, address(amm), 1 ether);

            SwapOrder memory swapOrder = SwapOrder({
                deadline: block.timestamp + 1,
                recipient: alice,
                amountSpecified: 1 ether,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(currency3),
                tokenOut: address(currency2)
            });

            BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
            FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

            SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

            bytes memory transferData = bytes("");

            _executeSingleProviderSingleSwap(
                swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
            );
        }

        uint160 currentPrice = singleProviderPool.getCurrentPriceX96(address(amm), poolId);
        assertEq(currentPrice, 79_228_162_514_264_337_593_543_950_336, "Price after swap should be set");
    }

    function test_collectSingleProviderLPFees() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);

        _addStandardSingleProviderLiquidity(poolId);

        _mintAndApprove(address(currency3), alice, address(amm), 1 ether);

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData memory swapHooksExtraData = _emptySwapHooksExtraData();

        bytes memory transferData = bytes("");

        _executeSingleProviderSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        (uint256 collected0, uint256 collected1) = _collectSingleProviderLPFees(poolId, allowedLP, bytes4(0));
        assertGt(collected0 + collected1, 0, "Collected fees should be greater than 0");
    }

    function test_collectFees_revert_NotAllowedProvider() public {
        bytes32 poolId = _createStandardSingleProviderPool();

        _collectSingleProviderLPFees(poolId, address(999_999), SingleProviderPool__NotAllowedProvider.selector);
    }

    function _collectSingleProviderLPFees(bytes32 poolId, address provider, bytes4 errorSelector)
        internal
        returns (uint256 collected0, uint256 collected1)
    {
        (collected0, collected1) =
            _collectSingleProviderLPFees(poolId, provider, address(0), _emptyLiquidityHooksExtraData(), errorSelector);
    }

    function _collectSingleProviderLPFees(
        bytes32 poolId,
        address provider,
        address liquidityHook,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        bytes4 errorSelector
    ) internal returns (uint256 collected0, uint256 collected1) {
        LiquidityCollectFeesParams memory liquidityParams = LiquidityCollectFeesParams(liquidityHook, poolId, type(uint256).max, type(uint256).max, bytes(""));

        changePrank(provider);
        (collected0, collected1) = _executeCollectFees(liquidityParams, liquidityHooksExtraData, errorSelector);
    }

    function _createSingleProviderPool(
        PoolCreationDetails memory details,
        bytes32 salt,
        bytes memory token0HookData,
        bytes memory token1HookData,
        bytes memory poolHookData,
        bytes4 errorSelector
    ) internal returns (bytes32) {
        details.poolParams = abi.encode(SingleProviderPoolCreationDetails({salt: salt, sqrtPriceRatioX96: 2**96}));

        return _createPool(details, token0HookData, token1HookData, poolHookData, errorSelector);
    }

    function _createSingleProviderPoolNoHookData(PoolCreationDetails memory details, bytes32 salt, bytes4 errorSelector)
        internal
        returns (bytes32)
    {
        return _createSingleProviderPool(details, salt, bytes(""), bytes(""), bytes(""), errorSelector);
    }

    function _createStandardSingleProviderPool() internal returns (bytes32) {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(currency3),
            token1: address(currency2),
            fee: 500,
            poolType: address(singleProviderPool),
            poolHook: address(spPoolHook),
            poolParams: bytes("")
        });

        return _createSingleProviderPoolNoHookData(details, keccak256(abi.encode("single-provider-test")), bytes4(0));
    }

    function _addSingleProviderLiquidity(
        SingleProviderLiquidityModificationParams memory spParams,
        LiquidityModificationParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        address provider,
        bytes4 errorSelector
    ) internal returns (uint256 deposit0, uint256 deposit1, uint256 fee0, uint256 fee1) {
        liquidityParams.poolParams = abi.encode(spParams);

        changePrank(provider);
        (deposit0, deposit1, fee0, fee1) = _executeAddLiquidity(liquidityParams, liquidityHooksExtraData, errorSelector);

        if (errorSelector == bytes4(0)) {
            assertEq(deposit0 + fee0, spParams.amount0, "SingleProvider Deposit Liquidity: deposit0 mismatch");
            assertEq(deposit1 + fee1, spParams.amount1, "SingleProvider Deposit Liquidity: deposit1 mismatch");
        }
    }

    function _addSingleProviderLiquidityNoHookData(
        uint256 amount0,
        uint256 amount1,
        LiquidityModificationParams memory liquidityParams,
        address provider,
        bytes4 errorSelector
    ) internal {
        SingleProviderLiquidityModificationParams memory spParams =
            SingleProviderLiquidityModificationParams({amount0: amount0, amount1: amount1});

        _addSingleProviderLiquidity(spParams, liquidityParams, _emptyLiquidityHooksExtraData(), provider, errorSelector);
    }

    function _addStandardSingleProviderLiquidity(bytes32 poolId) internal {
        SingleProviderLiquidityModificationParams memory spParams =
            SingleProviderLiquidityModificationParams({amount0: 100_000 ether, amount1: 100_000 ether});

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: abi.encode(spParams)
        });

        _addSingleProviderLiquidity(spParams, liquidityParams, _emptyLiquidityHooksExtraData(), allowedLP, bytes4(0));
    }

    function _removeSingleProviderLiquidity(
        uint256 amount0,
        uint256 amount1,
        LiquidityModificationParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        address provider,
        bytes4 errorSelector
    ) internal returns (uint256 withdraw0, uint256 withdraw1, uint256 fee0, uint256 fee1) {
        liquidityParams.poolParams = abi.encode(SingleProviderLiquidityModificationParams(amount0, amount1));

        changePrank(provider);
        (withdraw0, withdraw1, fee0, fee1) =
            _executeRemoveLiquidity(liquidityParams, liquidityHooksExtraData, errorSelector);

        if (errorSelector == bytes4(0)) {
            assertEq(withdraw0 + fee0, amount0, "SingleProvider Withdraw Liquidity: withdraw0 mismatch");
            assertEq(withdraw1 + fee1, amount1, "SingleProvider Withdraw Liquidity: withdraw1 mismatch");
        }
    }

    function _basicSwapContext(SwapOrder memory swapOrder) internal pure returns (SwapContext memory) {
        return SwapContext({
            executor: swapOrder.recipient,
            transferHandler: address(0),
            exchangeFeeRecipient: address(0),
            exchangeFeeBPS: 0,
            feeOnTopRecipient: address(0),
            feeOnTopAmount: 0,
            recipient: swapOrder.recipient,
            tokenIn: swapOrder.tokenIn,
            tokenOut: swapOrder.tokenOut,
            numberOfHops: 1
        });
    }

    function _hookPoolPriceParams(SwapTestCache memory cache, SwapOrder memory swapOrder)
        internal
        pure
        returns (ISingleProviderPoolHook.HookPoolPriceParams memory)
    {
        return ISingleProviderPoolHook.HookPoolPriceParams({
            inputSwap: cache.inputSwap,
            poolId: cache.poolId,
            tokenIn: swapOrder.tokenIn,
            tokenOut: swapOrder.tokenOut,
            amount: cache.amountSpecifiedAbs
        });
    }

    function _initializeSwapTestCache(
        bytes32 poolId,
        SwapTestCache memory cache,
        SwapOrder memory swapOrder,
        SwapHooksExtraData memory swapHooksExtraData
    ) internal {
        PoolState memory poolState = LimitBreakAMM(amm).getPoolState(poolId);

        _initializeProtocolFees(cache, swapOrder);

        cache.poolId = poolId;
        cache.poolFeeBPS = _getPoolFee(poolId);
        cache.inputSwap = swapOrder.amountSpecified > 0;
        cache.zeroForOne = swapOrder.tokenIn < swapOrder.tokenOut;
        cache.reserveOut = cache.zeroForOne ? poolState.reserve1 : poolState.reserve0;
        cache.amountSpecifiedAbs = uint256(cache.inputSwap ? swapOrder.amountSpecified : -swapOrder.amountSpecified);

        SwapContext memory context = _basicSwapContext(swapOrder);

        cache.sqrtPriceCurrentX96 =
            spPoolHook.getPoolPriceForSwap(context, _hookPoolPriceParams(cache, swapOrder), swapHooksExtraData.poolHook);

        if (cache.poolFeeBPS == 55_555) {
            cache.poolFeeBPS = uint16(
                ISingleProviderPoolHook(poolState.poolHook).getPoolFeeForSwap(
                    context,
                    HookPoolFeeParams(
                        cache.inputSwap, 0, poolId, swapOrder.tokenIn, swapOrder.tokenOut, cache.amountSpecifiedAbs
                    ),
                    swapHooksExtraData.poolHook
                )
            );
        }
    }

    function _executeSingleProviderSingleSwap(
        SwapOrder memory swapOrder,
        bytes32 poolId,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        SwapHooksExtraData memory swapHooksExtraData,
        bytes memory transferData,
        bytes4 errorSelector
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        SwapTestCache memory cache;

        _initializeSwapTestCache(poolId, cache, swapOrder, swapHooksExtraData);

        ProtocolFeeStructure memory protocolFeeStructure = _getProtocolFeeStructure(poolId, exchangeFee, feeOnTop);

        if (cache.inputSwap) {
            _applyBeforeSwapFeesSwapByInput(cache, swapOrder, exchangeFee, feeOnTop, protocolFeeStructure);

            _calculateSwapByInputSwap(cache, protocolFeeStructure);

            _applyAfterSwapFeesSwapByInput(cache, swapOrder);
        } else {
            _applyBeforeSwapFeesSwapByOutput(cache, swapOrder);

            _calculateSwapByOutputSwap(cache, protocolFeeStructure);

            _applyAfterSwapFeesSwapByOutput(cache, swapOrder, exchangeFee, feeOnTop, protocolFeeStructure);
        }

        changePrank(swapOrder.recipient);
        (amountIn, amountOut) = _executeSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, errorSelector
        );

        if (errorSelector == bytes4(0)) {
            if (swapOrder.amountSpecified > 0) {
                assertEq(amountOut, cache.amountUnspecifiedExpected, "SingeProvider Swap: Amount out mismatch");
            } else {
                assertEq(amountIn, cache.amountUnspecifiedExpected, "SingeProvider Swap: Amount in mismatch");
            }
            _verifyProtocolFees(swapOrder, cache);
        }
    }

    function _calculateSwapByInputSwap(SwapTestCache memory cache, ProtocolFeeStructure memory protocolFeeStructure)
        internal
        pure
    {
        uint256 amountIn = cache.amountSpecifiedAbs;
        _applyLPFeesSwapByInput(cache, protocolFeeStructure);
        _calculateFixedDeltaY(cache);
        if (cache.amountUnspecifiedExpected > cache.reserveOut) {
            uint256 expectedProtocolFees0 = cache.expectedProtocolFees0;
            uint256 expectedProtocolFees1 = cache.expectedProtocolFees1;
            cache.amountUnspecifiedExpected = cache.amountSpecifiedAbs;
            cache.amountSpecifiedAbs = cache.reserveOut;
            _calculateFixedDeltaX(cache);
            _applyLPFeesSwapByOutput(cache, protocolFeeStructure);
            cache.expectedProtocolFees0 -= expectedProtocolFees0;
            cache.expectedProtocolFees1 -= expectedProtocolFees1;
            (cache.amountUnspecifiedExpected, cache.amountSpecifiedAbs) =
                (cache.amountSpecifiedAbs, cache.amountUnspecifiedExpected);
            if (cache.amountSpecifiedAbs > amountIn) {
                cache.amountSpecifiedAbs = amountIn;
            }
        }
    }

    function _calculateSwapByOutputSwap(SwapTestCache memory cache, ProtocolFeeStructure memory protocolFeeStructure)
        internal
        pure
    {
        if (cache.amountSpecifiedAbs > cache.reserveOut) {
            cache.amountSpecifiedAbs = cache.reserveOut;
        }
        _calculateFixedDeltaX(cache);
        _applyLPFeesSwapByOutput(cache, protocolFeeStructure);
    }

    function _calculateFixedDeltaY(SwapTestCache memory cache) internal pure {
        uint160 sqrtPriceX96 = cache.sqrtPriceCurrentX96;
        uint256 amountOut;

        if (cache.zeroForOne) {
            amountOut = FullMath.mulDiv(cache.amountSpecifiedAbs, sqrtPriceX96, Q96);
            cache.amountUnspecifiedExpected = FullMath.mulDiv(amountOut, sqrtPriceX96, Q96);
        } else {
            amountOut = FullMath.mulDiv(cache.amountSpecifiedAbs, Q96, sqrtPriceX96);
            cache.amountUnspecifiedExpected = FullMath.mulDiv(amountOut, Q96, sqrtPriceX96);
        }
    }

    function _calculateFixedDeltaX(SwapTestCache memory cache) internal pure {
        uint160 sqrtPriceX96 = cache.sqrtPriceCurrentX96;
        uint256 amountIn;

        if (cache.zeroForOne) {
            amountIn = FullMath.mulDivRoundingUp(cache.amountSpecifiedAbs, Q96, sqrtPriceX96);
            cache.amountUnspecifiedExpected = FullMath.mulDivRoundingUp(amountIn, Q96, sqrtPriceX96);
        } else {
            amountIn = FullMath.mulDivRoundingUp(cache.amountSpecifiedAbs, sqrtPriceX96, Q96);
            cache.amountUnspecifiedExpected = FullMath.mulDivRoundingUp(amountIn, sqrtPriceX96, Q96);
        }
    }

    function _applyLPFeesSwapByInput(SwapTestCache memory cache, ProtocolFeeStructure memory protocolFeeStructure)
        internal
        pure
    {
        uint256 reserveAmount = FullMath.mulDiv(cache.amountSpecifiedAbs, MAX_BPS - cache.poolFeeBPS, MAX_BPS);
        uint256 lpFeeAmount = cache.amountSpecifiedAbs - reserveAmount;

        unchecked {
            cache.amountSpecifiedAbs -= lpFeeAmount;
        }
        if (protocolFeeStructure.lpFeeBPS > 0) {
            uint256 protocolFeeAmount = FullMath.mulDiv(lpFeeAmount, protocolFeeStructure.lpFeeBPS, MAX_BPS);
            unchecked {
                lpFeeAmount -= protocolFeeAmount;
            }
            if (cache.zeroForOne) {
                cache.expectedProtocolFees0 += protocolFeeAmount;
            } else {
                cache.expectedProtocolFees1 += protocolFeeAmount;
            }
        }
    }

    function _applyLPFeesSwapByOutput(SwapTestCache memory cache, ProtocolFeeStructure memory protocolFeeStructure)
        internal
        pure
    {
        uint256 lpFeeAmount =
            FullMath.mulDivRoundingUp(cache.amountUnspecifiedExpected, cache.poolFeeBPS, MAX_BPS - cache.poolFeeBPS);
        unchecked {
            cache.amountUnspecifiedExpected += lpFeeAmount;
        }
        if (protocolFeeStructure.lpFeeBPS > 0) {
            uint256 protocolFeeAmount = FullMath.mulDiv(lpFeeAmount, protocolFeeStructure.lpFeeBPS, MAX_BPS);
            unchecked {
                lpFeeAmount -= protocolFeeAmount;
            }
            if (cache.zeroForOne) {
                cache.expectedProtocolFees0 += protocolFeeAmount;
            } else {
                cache.expectedProtocolFees1 += protocolFeeAmount;
            }
        }
    }

    function _getPoolFee(bytes32 poolId) internal pure returns (uint16) {
        return PoolDecoder.getPoolFee(poolId);
    }
}
