pragma solidity ^0.8.24;

import "@limitbreak/lb-amm-core/test/LBAMMCorePoolBase.t.sol";

import {MAX_TICK, MIN_TICK} from "src/Constants.sol";
import "src/DataTypes.sol";
import {DynamicPoolType} from "src/DynamicPoolType.sol";

import {DynamicHelper} from "src/libraries/DynamicHelper.sol";
import {DynamicPoolDecoder} from "src/libraries/DynamicPoolDecoder.sol";

import {LiquidityMath} from "src/libraries/LiquidityMath.sol";
import {SqrtPriceMath} from "src/libraries/SqrtPriceMath.sol";
import {TickMath} from "src/libraries/TickMath.sol";

import {BrokenERC20Mock} from "test/mocks/ERC20Mock.sol";
import {ReceiverMockReject} from "test/mocks/ReceiverMock.sol";

import "@limitbreak/tm-core-lib/src/utils/math/UnsafeMath.sol";
import "../src/Errors.sol";

contract DynamicPoolTest is LBAMMCorePoolBaseTest {
    DynamicPoolType public dynamicPool;

    ERC20Mock test0;
    ERC20Mock test1;
    ERC20Mock test2;
    ERC20Mock test3;

    BrokenERC20Mock brokenToken0;
    address brokenTokenOwner;

    uint160 internal constant STANDARD_SQRT_PRICE = 1_120_455_419_495_722_798_374_638_764_549_163;
    int128 internal constant STANDARD_LIQUIDITY = 1_080_052_084_844_744_799_965;
    uint256 constant Q128 = 2 ** 128;

    function setUp() public virtual override {
        super.setUp();

        brokenToken0 = new BrokenERC20Mock("broken", "BRK", 18);
        brokenTokenOwner = brokenToken0.owner();

        address dynamicPoolAddress = address(1111);

        dynamicPool = new DynamicPoolType();
        vm.etch(dynamicPoolAddress, address(dynamicPool).code);
        dynamicPool = DynamicPoolType(dynamicPoolAddress);

        vm.label(address(dynamicPool), "Dynamic Pool");

        address test0Address = address(7776);
        address test1Address = address(7777);
        address test2Address = address(7778);
        address test3Address = address(7779);

        test0 = new ERC20Mock("Test0", "TST0", 18);
        test1 = new ERC20Mock("Test0", "TST0", 18);
        test2 = new ERC20Mock("Test0", "TST0", 18);
        test3 = new ERC20Mock("Test0", "TST0", 18);

        vm.etch(test0Address, address(test0).code);
        vm.etch(test1Address, address(test1).code);
        vm.etch(test2Address, address(test2).code);
        vm.etch(test3Address, address(test3).code);

        test0 = ERC20Mock(test0Address);
        test1 = ERC20Mock(test1Address);
        test2 = ERC20Mock(test2Address);
        test3 = ERC20Mock(test3Address);
    }

    function test_testDynamicFeeGrowthOverflow() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 10_000,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, STANDARD_SQRT_PRICE, bytes4(0));

        _mintAndApprove(address(usdc), alice, address(amm), type(uint256).max);
        _mintAndApprove(address(weth), alice, address(amm), type(uint256).max);

        DynamicLiquidityModificationParams memory dynamicParams =
            DynamicLiquidityModificationParams({tickLower: 191_140, tickUpper: 191_150, liquidityChange: 1, snapSqrtPriceX96: 0});

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: abi.encode(dynamicParams)
        });

        _executeAddLiquidity(liquidityParams, _emptyLiquidityHooksExtraData(), bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 290_000_000_000_000_000_000 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(usdc),
            tokenOut: address(weth)
        });

        SwapHooksExtraData memory swapHooksExtraData;
        bytes memory transferData = bytes("");

        // feeGrowthGlobalX128 will overflow during the second swap. If test is successful, it means the overflow is allowed to occur correctly.
        changePrank(swapOrder.recipient);
        for (uint256 i = 0; i < 2; i++) {
            _executeSingleSwap(
                swapOrder,
                poolId,
                BPSFeeWithRecipient(address(0), 0),
                FlatFeeWithRecipient(address(0), 0),
                swapHooksExtraData,
                transferData,
                bytes4(0)
            );
            _collectDynamicPoolLPFees(poolId, 191_140, 191_150, alice, bytes4(0));
        }
    }

    function test_computePoolId() public view {
        DynamicPoolCreationDetails memory dynamicDetails =
            DynamicPoolCreationDetails({tickSpacing: 10, sqrtPriceRatioX96: 1_111_111_111_111_111_111});

        PoolCreationDetails memory details = _standardPoolCreationDetails(dynamicDetails);

        bytes32 expectedPoolId = _generatePoolId(details, dynamicDetails);

        bytes32 actualPoolId = dynamicPool.computePoolId(details);

        assertEq(actualPoolId, expectedPoolId, "Computed pool ID does not match expected");
    }

    function test_createPool_poolIdsFlip() public {
        address token0 = address(currency3 < currency2 ? currency3 : currency2);
        address token1 = address(currency3 < currency2 ? currency2 : currency3);
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: token1,
            token1: token0,
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, STANDARD_SQRT_PRICE, bytes4(0));

        PoolState memory poolState = amm.getPoolState(poolId);

        assertEq(poolState.token0, token0);
        assertEq(poolState.token1, token1);
    }

    function test_createDynamicPool() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, STANDARD_SQRT_PRICE, bytes4(0));

        PoolState memory state = amm.getPoolState(poolId);

        assertEq(state.token0, details.token0, "Token0 mismatch");
        assertEq(state.token1, details.token1, "Token1 mismatch");
        assertEq(state.poolHook, details.poolHook, "Pool hook mismatch");
    }

    function test_creatDynamicPool_revert_PoolFeeGreaterThanMax() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 10_001,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(
            details, 10, MAX_SQRT_RATIO - 1, bytes4(LBAMM__PoolFeeMustBeLessThan100Percent.selector)
        );
    }

    function test_creatDynamicPool_revert_DynamicFeeInvalidConfig() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 55_555,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(details, 10, MAX_SQRT_RATIO - 1, bytes4(LBAMM__InvalidPoolFeeHook.selector));
    }

    function test_creatDynamicPool_revert_PairSameToken() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(usdc),
            fee: 50,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(details, 10, MAX_SQRT_RATIO - 1, bytes4(LBAMM__CannotPairIdenticalTokens.selector));
    }

    function test_creatDynamicPool_revert_PoolAlreadyInitialized() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 50,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(details, 10, MAX_SQRT_RATIO - 1, bytes4(0));
        _createDynamicPoolNoHookData(details, 10, MAX_SQRT_RATIO - 1, bytes4(LBAMM__PoolAlreadyExists.selector));
    }

    function test_createDynamicPool_revert_InvalidSqrtPriceHigh() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(details, 10, MAX_SQRT_RATIO, bytes4(DynamicPool__InvalidSqrtPriceX96.selector));
    }

    function test_createDynamicPool_revert_InvalidSqrtPriceLow() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(details, 10, MIN_SQRT_RATIO - 1, bytes4(DynamicPool__InvalidSqrtPriceX96.selector));
    }

    function test_createDynamicPool_revert_InvalidTickSpacingHigh() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(
            details, MAX_TICK_SPACING + 1, STANDARD_SQRT_PRICE, bytes4(DynamicPool__InvalidTickSpacing.selector)
        );
    }

    function test_createDynamicPool_revert_InvalidTickSpacingLow() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(details, 0, STANDARD_SQRT_PRICE, bytes4(DynamicPool__InvalidTickSpacing.selector));
    }

    function test_addLiquidityDynamicPool() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));
    }

    function test_addLiquidityDynamicPoolSnapPriceFromUpperLimit() public {
        bytes32 poolId = _createStandardDynamicPool(MAX_SQRT_RATIO - 1);

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        // Add liquidity with snap down
        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(291_150));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        // Add liquidity above, no snap
        dynamicParams =
            _initDynamicLiqParams(291_260, 291_270, STANDARD_LIQUIDITY, 0);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        // Revert when snapping into active liquidity
        dynamicParams =
            _initDynamicLiqParams(191_120, 191_150, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(191_149));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, DynamicPool__PriceCannotSnapWithLiquidity.selector);

        // Add liquidity, can snap to upper tick of a position
        dynamicParams =
            _initDynamicLiqParams(191_120, 191_150, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(191_150));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        // Revert when snapping onto lower tick of active position
        dynamicParams =
            _initDynamicLiqParams(200_000, 210_000, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(291_260));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, DynamicPool__PriceCannotSnapWithLiquidity.selector);

        // Add liquidity, can snap below lower tick of active position
        dynamicParams =
            _initDynamicLiqParams(200_000, 210_000, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(291_259));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));
    }

    function test_addLiquidityDynamicPoolSnapPriceFromLowerLimit() public {
        bytes32 poolId = _createStandardDynamicPool(MIN_SQRT_RATIO + 1);

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        // Add liquidity with snap up
        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(151_150));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        // Add liquidity below, no snap
        dynamicParams =
            _initDynamicLiqParams(141_260, 141_270, STANDARD_LIQUIDITY, 0);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        // Revert when snapping into active liquidity
        dynamicParams =
            _initDynamicLiqParams(191_120, 191_150, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(191_145));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, DynamicPool__PriceCannotSnapWithLiquidity.selector);

        // Add liquidity, can snap to upper tick of a position
        dynamicParams =
            _initDynamicLiqParams(140_260, 141_270, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(141_270));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        // Revert when snapping onto lower tick of active position
        dynamicParams =
            _initDynamicLiqParams(200_000, 210_000, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(191_140));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, DynamicPool__PriceCannotSnapWithLiquidity.selector);

        // Add liquidity, can snap below lower tick of active position
        dynamicParams =
            _initDynamicLiqParams(200_000, 210_000, STANDARD_LIQUIDITY, TickMath.getSqrtPriceAtTick(191_119));
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));
    }

    function test_AUDITC03_addLiquidity_WrappedNativeToken0() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(wrappedNative),
            token1: address(usdc),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, STANDARD_SQRT_PRICE, bytes4(0));

        _dealDepositApproveNative(alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(usdc), alice, address(amm), 1_000_000 ether);

        uint256 ammBalanceWrappedNativeBefore = wrappedNative.balanceOf(address(amm));
        uint256 ammBalanceUSDCBefore = usdc.balanceOf(address(amm));

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));
        
        uint256 ammBalanceWrappedNativeAfter = wrappedNative.balanceOf(address(amm));
        uint256 ammBalanceUSDCAfter = usdc.balanceOf(address(amm));

        assertGt(ammBalanceWrappedNativeAfter - ammBalanceWrappedNativeBefore, 0, "No Wrapped Native Deposited");
        assertGt(ammBalanceUSDCAfter - ammBalanceUSDCBefore, 0, "No USDC Deposited");
    }

    function test_createPoolWithLiquidityAndPriceSnap() public {
        _dealDepositApproveNative(alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(usdc), alice, address(amm), 1_000_000 ether);

        uint256 ammBalanceWrappedNativeBefore = wrappedNative.balanceOf(address(amm));
        uint256 ammBalanceUSDCBefore = usdc.balanceOf(address(amm));

        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(wrappedNative),
            token1: address(usdc),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        details.poolParams =
            abi.encode(DynamicPoolCreationDetails({tickSpacing: 10, sqrtPriceRatioX96: MAX_SQRT_RATIO}));

        bytes32 poolId = dynamicPool.computePoolId(details);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);
        LiquidityHooksExtraData memory liquidityHooksExtraData;

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY, STANDARD_SQRT_PRICE);

        changePrank(alice);

        // Expect success
        {
            dynamicParams.liquidityChange = STANDARD_LIQUIDITY;
            liquidityParams.poolParams = abi.encode(dynamicParams);
            bytes memory liquidityData = abi.encodeWithSelector(
                ILimitBreakAMMLiquidity.addLiquidity.selector,
                liquidityParams,
                liquidityHooksExtraData
            );

            (,uint256 deposit0, uint256 deposit1) = _createDynamicPoolWithAddLiquidity(
                details,
                10,
                STANDARD_SQRT_PRICE,
                bytes(""),
                bytes(""),
                bytes(""),
                liquidityData,
                bytes4(0)
            );
        
            uint256 ammBalanceWrappedNativeAfter = wrappedNative.balanceOf(address(amm));
            uint256 ammBalanceUSDCAfter = usdc.balanceOf(address(amm));

            assertEq(ammBalanceWrappedNativeAfter - ammBalanceWrappedNativeBefore, deposit0);
            assertEq(ammBalanceUSDCAfter - ammBalanceUSDCBefore, deposit1);

            assertGt(ammBalanceWrappedNativeAfter - ammBalanceWrappedNativeBefore, 0, "No Wrapped Native Deposited");
            assertGt(ammBalanceUSDCAfter - ammBalanceUSDCBefore, 0, "No USDC Deposited");
        }

        _dealDepositApproveNative(bob, address(amm), 1_000_000 ether);
        _mintAndApprove(address(usdc), bob, address(amm), 1_000_000 ether);
        // Bob cannot snap price with active liquidity
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, bob, DynamicPool__PriceCannotSnapWithLiquidity.selector);
        // Bob can add liquidity without snap price
        dynamicParams.snapSqrtPriceX96 = 0;
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, bob, bytes4(0));
    }

    function test_createPoolWithLiquidity() public {
        _dealDepositApproveNative(alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(usdc), alice, address(amm), 1_000_000 ether);

        uint256 ammBalanceWrappedNativeBefore = wrappedNative.balanceOf(address(amm));
        uint256 ammBalanceUSDCBefore = usdc.balanceOf(address(amm));

        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(wrappedNative),
            token1: address(usdc),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        details.poolParams =
            abi.encode(DynamicPoolCreationDetails({tickSpacing: 10, sqrtPriceRatioX96: STANDARD_SQRT_PRICE}));

        bytes32 poolId = dynamicPool.computePoolId(details);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);
        LiquidityHooksExtraData memory liquidityHooksExtraData;

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY);

        changePrank(alice);

        // Expect revert, no liquidity added, same pool
        {
            dynamicParams.liquidityChange = 0;
            liquidityParams.poolParams = abi.encode(dynamicParams);
            bytes memory liquidityData = abi.encodeWithSelector(
                ILimitBreakAMMLiquidity.addLiquidity.selector,
                liquidityParams,
                liquidityHooksExtraData
            );

            (,uint256 deposit0, uint256 deposit1) = _createDynamicPoolWithAddLiquidity(
                details,
                10,
                STANDARD_SQRT_PRICE,
                bytes(""),
                bytes(""),
                bytes(""),
                liquidityData,
                DynamicPool__PositionMustHaveLiquidity.selector
            );
        }

        // Expect revert, no liquidity added, different pool
        {
            bytes32 altPoolId = _createDynamicPoolNoHookData(details, 1, STANDARD_SQRT_PRICE, bytes4(0));
            liquidityParams.poolId = altPoolId;
            dynamicParams.liquidityChange = STANDARD_LIQUIDITY;
            liquidityParams.poolParams = abi.encode(dynamicParams);
            bytes memory liquidityData = abi.encodeWithSelector(
                ILimitBreakAMMLiquidity.addLiquidity.selector,
                liquidityParams,
                liquidityHooksExtraData
            );

            (,uint256 deposit0, uint256 deposit1) = _createDynamicPoolWithAddLiquidity(
                details,
                10,
                STANDARD_SQRT_PRICE,
                bytes(""),
                bytes(""),
                bytes(""),
                liquidityData,
                LBAMM__PoolCreationWithLiquidityDidNotAddLiquidity.selector
            );

            liquidityParams.poolId = poolId;
        }

        // Expect revert, invalid selector
        {
            dynamicParams.liquidityChange = 0;
            liquidityParams.poolParams = abi.encode(dynamicParams);
            bytes memory liquidityData = abi.encodeWithSelector(
                ILimitBreakAMMLiquidity.removeLiquidity.selector,
                liquidityParams,
                liquidityHooksExtraData
            );

            (,uint256 deposit0, uint256 deposit1) = _createDynamicPoolWithAddLiquidity(
                details,
                10,
                STANDARD_SQRT_PRICE,
                bytes(""),
                bytes(""),
                bytes(""),
                liquidityData,
                LBAMM__LiquidityDataDoesNotCallAddLiquidity.selector
            );
        }

        // Expect success
        {
            dynamicParams.liquidityChange = STANDARD_LIQUIDITY;
            liquidityParams.poolParams = abi.encode(dynamicParams);
            bytes memory liquidityData = abi.encodeWithSelector(
                ILimitBreakAMMLiquidity.addLiquidity.selector,
                liquidityParams,
                liquidityHooksExtraData
            );

            (,uint256 deposit0, uint256 deposit1) = _createDynamicPoolWithAddLiquidity(
                details,
                10,
                STANDARD_SQRT_PRICE,
                bytes(""),
                bytes(""),
                bytes(""),
                liquidityData,
                bytes4(0)
            );
        
            uint256 ammBalanceWrappedNativeAfter = wrappedNative.balanceOf(address(amm));
            uint256 ammBalanceUSDCAfter = usdc.balanceOf(address(amm));

            assertEq(ammBalanceWrappedNativeAfter - ammBalanceWrappedNativeBefore, deposit0);
            assertEq(ammBalanceUSDCAfter - ammBalanceUSDCBefore, deposit1);

            assertGt(ammBalanceWrappedNativeAfter - ammBalanceWrappedNativeBefore, 0, "No Wrapped Native Deposited");
            assertGt(ammBalanceUSDCAfter - ammBalanceUSDCBefore, 0, "No USDC Deposited");
        }
    }

    function test_addLiquidityDynamicPool_revert_PositionMustHaveLiquidity() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            DynamicLiquidityModificationParams({tickLower: 191_140, tickUpper: 191_150, liquidityChange: 0, snapSqrtPriceX96: 0});
        _addDynamicLiquidityNoHookData(
            dynamicParams, liquidityParams, alice, bytes4(DynamicPool__PositionMustHaveLiquidity.selector)
        );
    }

    function test_addLiquidityAndCollectFeesDynamicPoolToken1() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        _swapByInputOneForZeroSwapDynamicPoolNoExtraData(
            alice, poolId, BPSFeeWithRecipient(address(0), 0), FlatFeeWithRecipient(address(0), 0), bytes4(0)
        );

        (,,, uint256 fee1) = _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        assertGt(fee1, 0, "No Fee 1 Collected");
    }

    function test_addLiquidityAndCollectFeesDynamicPoolToken0() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

        int24 tickLower = poolState.tick - (10 * _getPoolTickSpacing(poolId));
        tickLower = _roundToTickSpacing(tickLower, _getPoolTickSpacing(poolId));
        int24 tickUpper = poolState.tick + (10 * _getPoolTickSpacing(poolId));
        tickUpper = _roundToTickSpacing(tickUpper, _getPoolTickSpacing(poolId));

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(tickLower, tickUpper, STANDARD_LIQUIDITY);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        _swapByInputSwapDynamicPoolNoExtraData(
            alice, poolId, BPSFeeWithRecipient(address(0), 0), FlatFeeWithRecipient(address(0), 0), bytes4(0)
        );

        (,, uint256 fee0,) = _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        assertGt(fee0, 0, "No Fee 0 Collected");
    }

    function test_collectFeesDynamicPool_TransferFailCollectTokensOwed() public virtual {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency2),
            token1: address(brokenToken0),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, STANDARD_SQRT_PRICE, bytes4(0));

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000_000_000 ether);
        _mintAndApprove(address(brokenToken0), alice, address(amm), 1_000_000_000_000 ether);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder =
            _createSwapOrder(alice, 1000, 0, address(brokenToken0), address(currency2), block.timestamp + 1);

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

        brokenToken0.setBroken(true);

        uint256 balanceAliceBefore = brokenToken0.balanceOf(alice);

        (uint256 fee0,) = _collectDynamicPoolLPFees(poolId, -887_270, 887_270, alice, bytes4(0));

        uint256 balanceAliceAfter = brokenToken0.balanceOf(alice);
        uint256 tokensOwed0 = amm.getTokensOwed(alice, address(brokenToken0));

        assertEq(balanceAliceAfter, balanceAliceBefore, "Tokens should not be collected");
        assertEq(tokensOwed0, fee0, "Tokens owed0 should be equal to fee0 because tokens were not collected");

        brokenToken0.setBroken(false);

        address[] memory tokens = new address[](1);
        tokens[0] = address(brokenToken0);
        _collectTokensOwed(alice, tokens, bytes4(0));

        balanceAliceAfter = brokenToken0.balanceOf(alice);
        tokensOwed0 = amm.getTokensOwed(alice, address(brokenToken0));

        assertEq(balanceAliceAfter, balanceAliceBefore + fee0, "Tokens should be collected");
        assertEq(tokensOwed0, 0, "Tokens owed0 should be cleared after collection");
    }

    function test_addLiquidity_revert_InsufficientLiquidityChange() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 10_000,
            minLiquidityAmount1: 10_000,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams =
            DynamicLiquidityModificationParams({tickLower: 191_140, tickUpper: 191_150, liquidityChange: 1, snapSqrtPriceX96: 0});
        _addDynamicLiquidityNoHookData(
            dynamicParams, liquidityParams, alice, bytes4(LBAMM__InsufficientLiquidityChange.selector)
        );
    }

    function test_addLiquidity_revert_InvalidTicks() public {
        bytes32 poolId = _createStandardDynamicPool();

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 10_000,
            minLiquidityAmount1: 10_000,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams =
            DynamicLiquidityModificationParams({tickLower: 191_150, tickUpper: 191_140, liquidityChange: 1, snapSqrtPriceX96: 0});

        _addDynamicLiquidityNoHookData(
            dynamicParams, liquidityParams, alice, bytes4(DynamicPool__MinTickMustBeLessThanMaxTick.selector)
        );

        dynamicParams.tickLower = MIN_TICK - 1;

        _addDynamicLiquidityNoHookData(
            dynamicParams, liquidityParams, alice, bytes4(DynamicPool__MinTickTooLow.selector)
        );

        dynamicParams.tickLower = 191_150;
        dynamicParams.tickUpper = MAX_TICK + 1;

        _addDynamicLiquidityNoHookData(
            dynamicParams, liquidityParams, alice, bytes4(DynamicPool__MaxTickTooHigh.selector)
        );
    }

    function test_addLiquidity_revert_NegativeLiquidityChange() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            DynamicLiquidityModificationParams({tickLower: 191_140, tickUpper: 191_150, liquidityChange: -1, snapSqrtPriceX96: 0});
        _addDynamicLiquidityNoHookData(
            dynamicParams, liquidityParams, alice, bytes4(DynamicPool__InvalidLiquidityChange.selector)
        );
    }

    function test_addLiquidityMultipleSimilarAmounts() public {
        PoolCreationDetails memory details =
            _standardPoolCreationDetails(DynamicPoolCreationDetails({tickSpacing: 0, sqrtPriceRatioX96: 0}));
        bytes32 poolId = _createDynamicPoolNoHookData(details, 1, STANDARD_SQRT_PRICE, bytes4(0));

        _mintAndApprove(address(usdc), alice, address(amm), 1_000_000_000_000_000e6);
        _mintAndApprove(address(weth), alice, address(amm), 1_000_000_000_000_000 ether);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            DynamicLiquidityModificationParams({tickLower: 0, tickUpper: 1, liquidityChange: 10_000_000, snapSqrtPriceX96: 0});
        (uint256 deposit0, uint256 deposit1, uint256 fee0, uint256 fee1) =
            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        dynamicParams.liquidityChange = 10_000_001;

        (deposit0, deposit1, fee0, fee1) =
            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));
    }

    function test_removeDynamicLiquidity() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY);
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

    function test_removeDynamicLiquidityAndCollectFeesToken0() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

        int24 tickLower = poolState.tick - (10 * _getPoolTickSpacing(poolId));
        tickLower = _roundToTickSpacing(tickLower, _getPoolTickSpacing(poolId));
        int24 tickUpper = poolState.tick + (10 * _getPoolTickSpacing(poolId));
        tickUpper = _roundToTickSpacing(tickUpper, _getPoolTickSpacing(poolId));

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(tickLower, tickUpper, STANDARD_LIQUIDITY);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        bytes32 positionId = EfficientHash.efficientHash(
            EfficientHash.efficientHash(
                bytes32(uint256(uint160(alice))), bytes32(uint256(uint160(address(0)))), liquidityParams.poolId
            ),
            bytes32(uint256(uint24(dynamicParams.tickLower))),
            bytes32(uint256(uint24(dynamicParams.tickUpper)))
        );

        DynamicPositionInfo memory position = dynamicPool.getPositionInfo(address(amm), positionId);

        _swapByInputSwapDynamicPoolNoExtraData(
            alice, poolId, BPSFeeWithRecipient(address(0), 0), FlatFeeWithRecipient(address(0), 0), bytes4(0)
        );

        (,, uint256 fee0,) = _removeDynamicLiquidity(
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

        assertGt(fee0, 0, "No Fee 0 Collected");
    }

    function test_removeDynamicLiquidityAndCollectFeesToken1() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        bytes32 positionId = EfficientHash.efficientHash(
            EfficientHash.efficientHash(
                bytes32(uint256(uint160(alice))), bytes32(uint256(uint160(address(0)))), liquidityParams.poolId
            ),
            bytes32(uint256(uint24(dynamicParams.tickLower))),
            bytes32(uint256(uint24(dynamicParams.tickUpper)))
        );

        DynamicPositionInfo memory position = dynamicPool.getPositionInfo(address(amm), positionId);

        _swapByInputOneForZeroSwapDynamicPoolNoExtraData(
            alice, poolId, BPSFeeWithRecipient(address(0), 0), FlatFeeWithRecipient(address(0), 0), bytes4(0)
        );

        (,,, uint256 fee1) = _removeDynamicLiquidity(
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

        assertGt(fee1, 0, "No Fee 1 Collected");
    }

    function test_removeDynamicLiquidity_revert_PositiveLiquidityDelta() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY);
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
                liquidityChange: int128(position.liquidity),
                snapSqrtPriceX96: 0
            }),
            liquidityParams,
            _emptyLiquidityHooksExtraData(),
            alice,
            bytes4(DynamicPool__InvalidLiquidityChange.selector)
        );
    }

    function test_removeDynamicLiquidity_revert_InsufficientLiquidityChange() public {
        bytes32 poolId = _createStandardDynamicPool();

        _setupStandardTokenApprovals();

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(191_140, 191_150, STANDARD_LIQUIDITY);
        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        liquidityParams.minLiquidityAmount0 = 10_000;
        liquidityParams.minLiquidityAmount1 = 10_000;

        _removeDynamicLiquidity(
            DynamicLiquidityModificationParams({
                tickLower: dynamicParams.tickLower,
                tickUpper: dynamicParams.tickUpper,
                liquidityChange: -int128(1),
                snapSqrtPriceX96: 0
            }),
            liquidityParams,
            _emptyLiquidityHooksExtraData(),
            alice,
            bytes4(LBAMM__InsufficientLiquidityChange.selector)
        );
    }

    function test_singleSwap_swapByInputZeroForOne() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByInputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInputZeroForOne_hopFee() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(usdc);
        hopTokens[1] = address(weth);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByInputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_nativeSwapByInput() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(currency2),
            token1: address(wrappedNative),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, 79_228_162_514_264_337_593_543_950_336, bytes4(0));

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _dealDepositApproveNative(alice, address(amm), 1_000_000 ether);
        vm.deal(alice, 1 ether);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        changePrank(alice);
        amm.singleSwap{value: 1000}(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1000,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(wrappedNative),
                tokenOut: address(currency2)
            }),
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes("")
        );
    }

    function test_singleSwap_nativeSwapByInputRefundExcess() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(currency2),
            token1: address(wrappedNative),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, 79_228_162_514_264_337_593_543_950_336, bytes4(0));

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _dealDepositApproveNative(alice, address(amm), 1_000_000 ether);
        vm.deal(alice, 1 ether);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        uint256 nativeBalanceBefore = address(alice).balance;

        changePrank(alice);
        amm.singleSwap{value: 10_000}(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1000,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(wrappedNative),
                tokenOut: address(currency2)
            }),
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes("")
        );

        uint256 nativeBalanceAfter = address(alice).balance;
        assertEq(nativeBalanceAfter, nativeBalanceBefore - 1000, "Native balance should only decrease by 1000");
    }

    function test_singleSwap_nativeSwapByInput_revert_ExcessRefundFailed() public {
        ReceiverMockReject receiver = new ReceiverMockReject();

        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(currency2),
            token1: address(wrappedNative),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, 79_228_162_514_264_337_593_543_950_336, bytes4(0));

        _mintAndApprove(address(currency2), address(receiver), address(amm), 1_000_000 ether);
        _dealDepositApproveNative(address(receiver), address(amm), 1_000_000 ether);
        vm.deal(address(receiver), 1 ether);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, address(receiver), bytes4(0));

        changePrank(address(receiver));
        vm.expectRevert(LBAMM__RefundFailed.selector);
        amm.singleSwap{value: 10_000}(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: address(receiver),
                amountSpecified: 1000,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(wrappedNative),
                tokenOut: address(currency2)
            }),
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes("")
        );
    }

    function test_singleSwap_nativeSwapByInput_revert_NotEnoughValue() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(currency2),
            token1: address(wrappedNative),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, 79_228_162_514_264_337_593_543_950_336, bytes4(0));

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _dealDepositApproveNative(alice, address(amm), 1_000_000 ether);
        vm.deal(alice, 1 ether);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        changePrank(alice);
        vm.expectRevert(LBAMM__InsufficientValue.selector);
        amm.singleSwap{value: 10}(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1000,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(wrappedNative),
                tokenOut: address(currency2)
            }),
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes("")
        );
    }

    function test_singleSwap_swapByOutputZeroForOne() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByOutputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByOutputZeroForOne_hopFee() public virtual {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(usdc);
        hopTokens[1] = address(weth);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByOutputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInputOneForZero() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByInputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByOutputOneForZero() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByOutputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInputZeroForOneExchangeFee() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 100, recipient: exchangeFeeRecipient});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByInputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByOutputZeroForOneExchangeFee() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 100, recipient: exchangeFeeRecipient});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByOutputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInputOneForZeroExchangeFee() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 100, recipient: exchangeFeeRecipient});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByInputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByOutputOneForZeroExchangeFee() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 100, recipient: exchangeFeeRecipient});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByOutputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInputZeroForOneFeeOnTop() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 1000, recipient: feeOnTopRecipient});

        _swapByInputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByOutputZeroForOneFeeOnTop() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 1000, recipient: feeOnTopRecipient});

        _swapByOutputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInputOneForZeroFeeOnTop() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 1000, recipient: feeOnTopRecipient});

        _swapByInputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByOutputOneForZeroFeeOnTop() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 1000, recipient: feeOnTopRecipient});

        _swapByOutputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInputZeroForOneExchangeFeeAndFeeOnTop() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 100, recipient: exchangeFeeRecipient});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 1000, recipient: feeOnTopRecipient});

        _swapByInputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByOutputZeroForOneExchangeFeeAndFeeOnTop() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 100, recipient: exchangeFeeRecipient});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 1000, recipient: feeOnTopRecipient});

        _swapByOutputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInputOneForZeroExchangeFeeAndFeeOnTop() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 100, recipient: exchangeFeeRecipient});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 1000, recipient: feeOnTopRecipient});

        _swapByInputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByOutputOneForZeroExchangeFeeAndFeeOnTop() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 100, recipient: exchangeFeeRecipient});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 1000, recipient: feeOnTopRecipient});

        _swapByOutputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
    }

    function test_singleSwap_swapByInput_partialFill() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addDynamicLiquidityPositionsAcrossTickBoundaries(poolId);

        SwapOrder memory swapOrder =
            _createSwapOrder(alice, 1000 ether, 0, address(usdc), address(weth), block.timestamp + 1000);

        SwapHooksExtraData memory swapHooksExtraData;

        uint160 priceLimit = dynamicPool.getCurrentPriceX96(address(amm), poolId) * 9999 / 10_000;

        swapHooksExtraData.poolType = abi.encode(priceLimit);

        bytes memory transferData = bytes("");
        BPSFeeWithRecipient memory exchangeFee;
        FlatFeeWithRecipient memory feeOnTop;

        changePrank(swapOrder.recipient);
        (uint256 amountIn,) = _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        assertLt(amountIn, uint256(swapOrder.amountSpecified), "Full Amount In Used");
    }

    function test_singleSwap_swapByInput_partialFillBelowMinimumSpecified() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addDynamicLiquidityPositionsAcrossTickBoundaries(poolId);

        SwapOrder memory swapOrder =
            _createSwapOrder(alice, 1000 ether, 24000000000000, 0, address(usdc), address(weth), block.timestamp + 1000);

        SwapHooksExtraData memory swapHooksExtraData;

        uint160 priceLimit = dynamicPool.getCurrentPriceX96(address(amm), poolId) * 9999 / 10_000;

        swapHooksExtraData.poolType = abi.encode(priceLimit);

        bytes memory transferData = bytes("");
        BPSFeeWithRecipient memory exchangeFee;
        FlatFeeWithRecipient memory feeOnTop;

        changePrank(swapOrder.recipient);
        uint256 snapshotId = vm.snapshot();
        _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        vm.revertTo(snapshotId);
        swapOrder.minAmountSpecified = 25000000000000;
        _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, LBAMM__PartialFillLessThanMinimumSpecified.selector
        );
    }

    function test_singleSwap_swapByOutput_partialFill() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addDynamicLiquidityPositionsAcrossTickBoundaries(poolId);

        SwapOrder memory swapOrder = _createSwapOrder(
            alice, -5000 ether, type(uint256).max, address(usdc), address(weth), block.timestamp + 1000
        );

        SwapHooksExtraData memory swapHooksExtraData;

        uint160 priceLimit = dynamicPool.getCurrentPriceX96(address(amm), poolId) * 9999 / 10_000;

        swapHooksExtraData.poolType = abi.encode(priceLimit);

        bytes memory transferData = bytes("");
        BPSFeeWithRecipient memory exchangeFee;
        FlatFeeWithRecipient memory feeOnTop;

        changePrank(swapOrder.recipient);
        (, uint256 amountOut) = _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        assertLt(amountOut, uint256(-swapOrder.amountSpecified), "Full Amount Out Received");
    }

    function test_singleSwap_swapByInput_revert_LimitAmountNotMet() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        changePrank(alice);
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1,
                minAmountSpecified: 0,
                limitAmount: 2,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            poolId,
            BPSFeeWithRecipient({recipient: address(0), BPS: 0}),
            FlatFeeWithRecipient({recipient: address(0), amount: 0}),
            _emptySwapHooksExtraData(),
            bytes(""),
            LBAMM__LimitAmountNotMet.selector
        );
    }

    function test_singleSwap_swapByInput_revert_feeOnTopGreaterThanAmountSpecified() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        changePrank(alice);
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1000,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            poolId,
            BPSFeeWithRecipient({recipient: address(0), BPS: 0}),
            FlatFeeWithRecipient({recipient: address(feeOnTopRecipient), amount: 1001}),
            _emptySwapHooksExtraData(),
            bytes(""),
            LBAMM__FeeAmountExceedsInputAmount.selector
        );
    }

    function test_singleSwap_swapByInput_revert_ExchangeFeeGreaterThanMaxFee() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        changePrank(alice);
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1,
                minAmountSpecified: 0,
                limitAmount: 2,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            poolId,
            BPSFeeWithRecipient({recipient: address(exchangeFeeRecipient), BPS: 10_001}),
            FlatFeeWithRecipient({recipient: address(0), amount: 0}),
            _emptySwapHooksExtraData(),
            bytes(""),
            LBAMM__FeeAmountExceedsMaxFee.selector
        );
    }

    function test_AUDITI04_singleSwap_swapByOutput_revert_ExchangeFeeEqualsMaxFee() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        changePrank(alice);
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: -1,
                minAmountSpecified: 0,
                limitAmount: type(uint256).max,
                tokenIn: address(weth),
                tokenOut: address(usdc)
            }),
            poolId,
            BPSFeeWithRecipient({recipient: address(exchangeFeeRecipient), BPS: 10_000}),
            FlatFeeWithRecipient({recipient: address(0), amount: 0}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(LBAMM__FeeAmountExceedsMaxFee.selector)
        );
    }

    function test_singleSwap_swapByInput_revert_ExchangeFeeRecipientAddressZero() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        changePrank(alice);
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1,
                minAmountSpecified: 0,
                limitAmount: 2,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            poolId,
            BPSFeeWithRecipient({recipient: address(0), BPS: 10}),
            FlatFeeWithRecipient({recipient: address(0), amount: 0}),
            _emptySwapHooksExtraData(),
            bytes(""),
            LBAMM__FeeRecipientCannotBeAddressZero.selector
        );
    }

    function test_singleSwap_swapByInput_zeroForOne_revert_priceLimitAbovePrice() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee;

        FlatFeeWithRecipient memory feeOnTop;

        SwapOrder memory swapOrder =
            _createSwapOrder(alice, 1000e6, 0, address(usdc), address(weth), block.timestamp + 1);

        SwapHooksExtraData memory swapHooksExtraData;
        swapHooksExtraData.poolType = abi.encode(dynamicPool.getCurrentPriceX96(address(amm), poolId) * 10_001 / 10_000);
        bytes memory transferData = bytes("");

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            exchangeFee,
            feeOnTop,
            swapHooksExtraData,
            transferData,
            bytes4(DynamicPool__PoolStartPriceExceedsSwapLimitPrice.selector)
        );
    }

    function test_singleSwap_swapByInput_oneForZero_revert_priceLimitBelowPrice() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee;

        FlatFeeWithRecipient memory feeOnTop;

        SwapOrder memory swapOrder =
            _createSwapOrder(alice, 1000e6, 0, address(weth), address(usdc), block.timestamp + 1);

        SwapHooksExtraData memory swapHooksExtraData;
        swapHooksExtraData.poolType = abi.encode(dynamicPool.getCurrentPriceX96(address(amm), poolId) * 9999 / 10_000);
        bytes memory transferData = bytes("");

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            exchangeFee,
            feeOnTop,
            swapHooksExtraData,
            transferData,
            bytes4(DynamicPool__PoolStartPriceExceedsSwapLimitPrice.selector)
        );
    }

    function test_singleSwap_swapByInput_revert_FeeOnTopRecipientAddressZero() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        changePrank(alice);
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1,
                minAmountSpecified: 0,
                limitAmount: 2,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            poolId,
            BPSFeeWithRecipient({recipient: address(0), BPS: 0}),
            FlatFeeWithRecipient({recipient: address(0), amount: 100}),
            _emptySwapHooksExtraData(),
            bytes(""),
            LBAMM__FeeRecipientCannotBeAddressZero.selector
        );
    }

    function test_singleSwap_swapByInput_revert_PoolIdDoesNotMatchPath() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        changePrank(alice);
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1_000_000,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(usdc)
            }),
            poolId,
            BPSFeeWithRecipient({recipient: address(0), BPS: 0}),
            FlatFeeWithRecipient({recipient: address(0), amount: 0}),
            _emptySwapHooksExtraData(),
            bytes(""),
            LBAMM__InvalidPoolId.selector
        );
    }

    function test_swapByInputSwapDirectCall_revert_poolFeeBPSGreaterThanMaxFee() public {
        vm.expectRevert();
        dynamicPool.swapByInput(
            SwapContext(address(0), address(0), address(0), 0, address(0), 0, address(0), address(0), address(0), 1),
            bytes32(0),
            true,
            1,
            10_001,
            0,
            bytes("")
        );
    }

    function test_swapByOutputSwapDirectCall_revert_poolFeeBPSGreaterThanMaxFee() public {
        vm.expectRevert();
        dynamicPool.swapByOutput(
            SwapContext(address(0), address(0), address(0), 0, address(0), 0, address(0), address(0), address(0), 1),
            bytes32(0),
            true,
            1,
            10_001,
            0,
            bytes("")
        );
    }

    function test_singleSwap_revert_CallerBalanceBelowAmountSpecified() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        changePrank(carol);
        usdc.approve(address(amm), 1_000_000e6);

        _swapByInputSwapDynamicPoolNoExtraData(carol, poolId, exchangeFee, feeOnTop, bytes4(PANIC_SELECTOR));
    }

    function test_singleSwap_revert_LimitAmountsNotMet() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapOrder memory swapOrder =
            _createSwapOrder(alice, 1000e6, 10 ether, address(usdc), address(weth), block.timestamp + 1);

        SwapHooksExtraData memory swapHooksExtraData;
        bytes memory transferData = bytes("");

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            exchangeFee,
            feeOnTop,
            swapHooksExtraData,
            transferData,
            bytes4(LBAMM__LimitAmountNotMet.selector)
        );

        swapOrder.amountSpecified = -int256(swapOrder.amountSpecified);
        swapOrder.limitAmount = 0;

        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            exchangeFee,
            feeOnTop,
            swapHooksExtraData,
            transferData,
            bytes4(LBAMM__LimitAmountExceeded.selector)
        );
    }

    function test_collectFeesDynamicPool() public {
        bytes32 poolId = _createStandardDynamicPool();

        (,,,, int24 tickLower, int24 tickUpper) = _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByInputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));

        (uint256 fee0,) = _collectDynamicPoolLPFees(poolId, tickLower, tickUpper, alice, bytes4(0));

        assertGt(fee0, 0, "Fee0 should be greater than 0");
    }

    function test_collectFeesDynamicPoolWrappedNative() public virtual {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(currency2),
            token1: address(wrappedNative),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        bytes32 poolId = _createDynamicPoolNoHookData(details, 10, 79_228_162_514_264_337_593_543_950_336, bytes4(0));

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _dealDepositApproveNative(alice, address(amm), 1_000_000 ether);
        vm.deal(alice, 1 ether);

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        changePrank(alice);
        amm.singleSwap{value: 1000}(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1000,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(wrappedNative),
                tokenOut: address(currency2)
            }),
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes("")
        );
        _collectDynamicPoolLPFees(poolId, -887_270, 887_270, alice, bytes4(0));
    }

    function test_collectFeesDynamicPoolToken1() public {
        bytes32 poolId = _createStandardDynamicPool();

        (,,,, int24 tickLower, int24 tickUpper) = _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByInputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));

        (, uint256 fee1) = _collectDynamicPoolLPFees(poolId, tickLower, tickUpper, alice, bytes4(0));

        assertGt(fee1, 0, "Fee1 should be greater than 0");
    }

    function test_collectFeesDynamicPoolBothTokens() public {
        bytes32 poolId = _createStandardDynamicPool();

        (,,,, int24 tickLower, int24 tickUpper) = _addStandardDynamicLiquidity(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _swapByInputSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));
        _swapByInputOneForZeroSwapDynamicPoolNoExtraData(alice, poolId, exchangeFee, feeOnTop, bytes4(0));

        (uint256 fee0, uint256 fee1) = _collectDynamicPoolLPFees(poolId, tickLower, tickUpper, alice, bytes4(0));

        assertGt(fee0, 0, "Fee0 shoudl be greater than 0");
        assertGt(fee1, 0, "Fee1 should be greater than 0");
    }

    function test_multiSwap_swapByInput_base() public {
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = _createStandardDynamicPool();
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(test0),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        poolIds[1] = _createDynamicPoolNoHookData(details, 10, _calculatePriceLimit(1, 3), bytes4(0));

        _addStandardDynamicLiquidity(poolIds[0]);

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolIds[1],
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), liquidityParams.poolId);

        int24 tickLower = poolState.tick - (10 * _getPoolTickSpacing(liquidityParams.poolId));
        tickLower = _roundToTickSpacing(tickLower, _getPoolTickSpacing(liquidityParams.poolId));
        int24 tickUpper = poolState.tick + (10 * _getPoolTickSpacing(liquidityParams.poolId));
        tickUpper = _roundToTickSpacing(tickUpper, _getPoolTickSpacing(liquidityParams.poolId));

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(tickLower, tickUpper, STANDARD_LIQUIDITY);

        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData[] memory swapHooksExtraDatas = new SwapHooksExtraData[](2);

        _setupStandardTokenApprovals();
        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);

        _executeDynamicPoolMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 1000e6,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(test0)
            }),
            poolIds,
            exchangeFee,
            feeOnTop,
            swapHooksExtraDatas,
            bytes(""),
            bytes4(0)
        );
    }

    function test_multiSwap_variousHookDataLength() public {
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = _createStandardDynamicPool();
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(test0),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        poolIds[1] = _createDynamicPoolNoHookData(details, 10, STANDARD_SQRT_PRICE, bytes4(0));

        _addStandardDynamicLiquidity(poolIds[0]);

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolIds[1],
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);

        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData[] memory swapHooksExtraDatas = new SwapHooksExtraData[](2);
        swapHooksExtraDatas[0] = SwapHooksExtraData({
            tokenInHook: bytes("1"),
            tokenOutHook: bytes("11"),
            poolHook: bytes("111"),
            poolType: bytes("")
        });
        swapHooksExtraDatas[1] = SwapHooksExtraData({
            tokenInHook: bytes("1"),
            tokenOutHook: bytes("111"),
            poolHook: bytes("11"),
            poolType: bytes("")
        });

        _setupStandardTokenApprovals();
        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);

        _executeDynamicPoolMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 5000e6,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(test0)
            }),
            poolIds,
            exchangeFee,
            feeOnTop,
            swapHooksExtraDatas,
            bytes(""),
            bytes4(0)
        );

        swapHooksExtraDatas[0] = SwapHooksExtraData({
            tokenInHook: bytes("111"),
            tokenOutHook: bytes("11"),
            poolHook: bytes("1"),
            poolType: bytes("")
        });

        swapHooksExtraDatas[1] = SwapHooksExtraData({
            tokenInHook: bytes("11"),
            tokenOutHook: bytes("1"),
            poolHook: bytes("1"),
            poolType: bytes("1111")
        });

        _executeDynamicPoolMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: 5000e6,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(test0)
            }),
            poolIds,
            exchangeFee,
            feeOnTop,
            swapHooksExtraDatas,
            bytes(""),
            bytes4(0)
        );
    }

    function test_multiSwap_swapByOutput_base() public {
        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = _createStandardDynamicPool();
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(test0),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        poolIds[1] = _createDynamicPoolNoHookData(details, 10, _calculatePriceLimit(1, 3), bytes4(0));

        _addStandardDynamicLiquidity(poolIds[0]);

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolIds[1],
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), liquidityParams.poolId);

        int24 tickLower = poolState.tick - (10 * _getPoolTickSpacing(liquidityParams.poolId));
        tickLower = _roundToTickSpacing(tickLower, _getPoolTickSpacing(liquidityParams.poolId));
        int24 tickUpper = poolState.tick + (10 * _getPoolTickSpacing(liquidityParams.poolId));
        tickUpper = _roundToTickSpacing(tickUpper, _getPoolTickSpacing(liquidityParams.poolId));

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(tickLower, tickUpper, STANDARD_LIQUIDITY);

        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData[] memory swapHooksExtraDatas = new SwapHooksExtraData[](2);
        swapHooksExtraDatas[0] = _emptySwapHooksExtraData();
        swapHooksExtraDatas[1] = _emptySwapHooksExtraData();

        _setupStandardTokenApprovals();
        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);

        _executeDynamicPoolMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1000,
                recipient: alice,
                amountSpecified: -100e6,
                minAmountSpecified: 0,
                limitAmount: type(uint256).max,
                tokenIn: address(test0),
                tokenOut: address(usdc)
            }),
            poolIds,
            exchangeFee,
            feeOnTop,
            swapHooksExtraDatas,
            bytes(""),
            bytes4(0)
        );
    }

    function test_multiSwap_swapByInput_onePool() public {
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolIds[0]);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData[] memory swapHooksExtraDatas = new SwapHooksExtraData[](1);
        swapHooksExtraDatas[0] = _emptySwapHooksExtraData();

        _setupStandardTokenApprovals();

        _executeDynamicPoolMultiSwap(
            _createSwapOrder(alice, 1_000_000e6, 0, address(usdc), address(weth), block.timestamp + 1),
            poolIds,
            exchangeFee,
            feeOnTop,
            swapHooksExtraDatas,
            bytes(""),
            bytes4(0)
        );
    }

    function test_multiSwap_swapByOutput_onePool() public {
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = _createStandardDynamicPool();

        _addStandardDynamicLiquidity(poolIds[0]);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData[] memory swapHooksExtraDatas = new SwapHooksExtraData[](1);
        swapHooksExtraDatas[0] = _emptySwapHooksExtraData();

        _setupStandardTokenApprovals();

        _executeDynamicPoolMultiSwap(
            _createSwapOrder(alice, -1000e6, type(uint256).max, address(weth), address(usdc), block.timestamp + 1),
            poolIds,
            exchangeFee,
            feeOnTop,
            swapHooksExtraDatas,
            bytes(""),
            bytes4(0)
        );
    }

    function test_multiSwap_swapByInput_threePools() public {
        {
            _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);
            _mintAndApprove(address(test1), alice, address(amm), 1_000_000 ether);
            _mintAndApprove(address(test2), alice, address(amm), 1_000_000 ether);
            _mintAndApprove(address(test3), alice, address(amm), 1_000_000 ether);
        }

        bytes32[] memory poolIds = new bytes32[](3);

        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(test0),
            token1: address(test1),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        poolIds[0] = _createDynamicPoolNoHookData(details, 10, uint160(0x1000000000000000000000000), bytes4(0));

        details.token0 = address(test1);
        details.token1 = address(test2);

        poolIds[1] = _createDynamicPoolNoHookData(details, 10, uint160(0x1000000000000000000000000), bytes4(0));

        details.token0 = address(test2);
        details.token1 = address(test3);

        poolIds[2] = _createDynamicPoolNoHookData(details, 10, uint160(0x1000000000000000000000000), bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolIds[0],
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        liquidityParams.poolId = poolIds[1];

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        liquidityParams.poolId = poolIds[2];

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData[] memory swapHooksExtraDatas = new SwapHooksExtraData[](3);

        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(test1), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(test2), alice, address(amm), 1_000_000 ether);

        _executeDynamicPoolMultiSwap(
            _createSwapOrder(alice, 1_000_000e6, 0, address(test0), address(test3), block.timestamp + 1),
            poolIds,
            exchangeFee,
            feeOnTop,
            swapHooksExtraDatas,
            bytes(""),
            bytes4(0)
        );
    }

    function test_multiSwap_swapByOutput_threePools() public {
        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(test1), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(test2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(test3), alice, address(amm), 1_000_000 ether);

        bytes32[] memory poolIds = new bytes32[](3);

        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(test0),
            token1: address(test1),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });

        poolIds[0] = _createDynamicPoolNoHookData(details, 10, uint160(0x1000000000000000000000000), bytes4(0));

        details.token0 = address(test1);
        details.token1 = address(test2);

        poolIds[1] = _createDynamicPoolNoHookData(details, 10, uint160(0x1000000000000000000000000), bytes4(0));

        details.token0 = address(test2);
        details.token1 = address(test3);

        poolIds[2] = _createDynamicPoolNoHookData(details, 10, uint160(0x1000000000000000000000000), bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolIds[0],
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(-887_270, 887_270, STANDARD_LIQUIDITY);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        liquidityParams.poolId = poolIds[1];

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        liquidityParams.poolId = poolIds[2];

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapHooksExtraData[] memory swapHooksExtraDatas = new SwapHooksExtraData[](3);

        _mintAndApprove(address(test0), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(test1), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(test2), alice, address(amm), 1_000_000 ether);

        _executeDynamicPoolMultiSwap(
            _createSwapOrder(alice, -1000e6, type(uint256).max, address(test3), address(test0), block.timestamp + 1),
            poolIds,
            exchangeFee,
            feeOnTop,
            swapHooksExtraDatas,
            bytes(""),
            bytes4(0)
        );
    }

    /////////////////////////////////////////
    //            HELPERS
    /////////////////////////////////////////

    function _standardLiquidityModificationParams(bytes32 poolId)
        internal
        pure
        returns (LiquidityModificationParams memory)
    {
        return LiquidityModificationParams({
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
    }

    function _initDynamicLiqParams(int24 tickLower, int24 tickUpper, int128 liquidityChange)
        internal
        pure
        returns (DynamicLiquidityModificationParams memory)
    {
        return _initDynamicLiqParams(tickLower, tickUpper, liquidityChange, 0);
    }

    function _initDynamicLiqParams(int24 tickLower, int24 tickUpper, int128 liquidityChange, uint160 snapSqrtPriceX96)
        internal
        pure
        returns (DynamicLiquidityModificationParams memory)
    {
        return DynamicLiquidityModificationParams({
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidityChange: liquidityChange,
            snapSqrtPriceX96: snapSqrtPriceX96
        });
    }

    function _standardPoolCreationDetails(DynamicPoolCreationDetails memory dynamicDetails)
        internal
        view
        returns (PoolCreationDetails memory)
    {
        return PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: abi.encode(dynamicDetails)
        });
    }

    function _createSwapOrder(
        address recipient,
        int256 amountSpecified,
        uint256 minAmountSpecified,
        uint256 limitAmount,
        address tokenIn,
        address tokenOut,
        uint256 deadline
    ) internal pure returns (SwapOrder memory) {
        return SwapOrder({
            deadline: deadline,
            recipient: recipient,
            amountSpecified: amountSpecified,
            minAmountSpecified: minAmountSpecified,
            limitAmount: limitAmount,
            tokenIn: tokenIn,
            tokenOut: tokenOut
        });
    }

    function _createSwapOrder(
        address recipient,
        int256 amountSpecified,
        uint256 limitAmount,
        address tokenIn,
        address tokenOut,
        uint256 deadline
    ) internal pure returns (SwapOrder memory) {
        return _createSwapOrder(recipient, amountSpecified, 0, limitAmount, tokenIn, tokenOut, deadline);
    }

    function _setupStandardTokenApprovals() internal {
        _mintAndApprove(address(usdc), alice, address(amm), 1_000_000_000_000 ether);
        _mintAndApprove(address(weth), alice, address(amm), 1_000_000_000_000 ether);
    }

    function _collectDynamicPoolLPFees(
        bytes32 poolId,
        int24 tickLower,
        int24 tickUpper,
        address provider,
        bytes4 errorSelector
    ) internal returns (uint256 collected0, uint256 collected1) {
        LiquidityCollectFeesParams memory liquidityParams = LiquidityCollectFeesParams({
            poolId: poolId,
            liquidityHook: address(0),
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: abi.encode(DynamicLiquidityCollectFeesParams(tickLower, tickUpper))
        });

        changePrank(provider);
        (collected0, collected1) = _executeCollectFees(liquidityParams, _emptyLiquidityHooksExtraData(), errorSelector);
    }

    function _createDynamicPool(
        PoolCreationDetails memory details,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        bytes memory token0HookData,
        bytes memory token1HookData,
        bytes memory poolHookData,
        bytes4 errorSelector
    ) internal returns (bytes32 poolId) {
        details.poolParams =
            abi.encode(DynamicPoolCreationDetails({tickSpacing: tickSpacing, sqrtPriceRatioX96: sqrtPriceX96}));
        poolId = _createPool(details, token0HookData, token1HookData, poolHookData, errorSelector);
    }

    function _createDynamicPoolWithAddLiquidity(
        PoolCreationDetails memory details,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        bytes memory token0HookData,
        bytes memory token1HookData,
        bytes memory poolHookData,
        bytes memory liquidityData,
        bytes4 errorSelector
    ) internal returns (bytes32 poolId, uint256 deposit0, uint256 deposit1) {
        details.poolParams =
            abi.encode(DynamicPoolCreationDetails({tickSpacing: tickSpacing, sqrtPriceRatioX96: sqrtPriceX96}));
        (poolId, deposit0, deposit1) = _createPoolWithAddLiquidity(details, token0HookData, token1HookData, poolHookData, liquidityData, errorSelector);
    }

    function _createDynamicPoolNoHookData(
        PoolCreationDetails memory details,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        bytes4 errorSelector
    ) internal returns (bytes32 poolId) {
        poolId = _createDynamicPool(details, tickSpacing, sqrtPriceX96, bytes(""), bytes(""), bytes(""), errorSelector);
    }

    function _createStandardDynamicPool() internal returns (bytes32 poolId) {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        poolId = _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));
    }

    function _createStandardDynamicPool(uint160 initialSqrtPriceX96) internal returns (bytes32 poolId) {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(usdc),
            token1: address(weth),
            fee: 500,
            poolType: address(dynamicPool),
            poolHook: address(0),
            poolParams: bytes("")
        });
        poolId = _createDynamicPoolNoHookData(details, 10, initialSqrtPriceX96, bytes4(0));
    }

    function _addDynamicLiquidityPositionsAcrossTickBoundaries(bytes32 poolId)
        internal
        returns (uint256 deposit0, uint256 deposit1, uint256 fee0, uint256 fee1)
    {
        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

        // build a tick range that crosses tick boundaries
        DynamicLiquidityModificationParams memory dynamicParams = _initDynamicLiqParams(0, 0, 1_000_000_000_000_000_000);

        dynamicParams.tickLower = poolState.tick - (3 * 10);
        dynamicParams.tickUpper = poolState.tick + (3 * 10);
        dynamicParams.tickLower = _roundToTickSpacing(dynamicParams.tickLower, 10);
        dynamicParams.tickUpper = _roundToTickSpacing(dynamicParams.tickUpper, 10);
        dynamicParams.liquidityChange = STANDARD_LIQUIDITY;

        _mintAndApprove(address(usdc), alice, address(amm), 10_000_000 ether);
        _mintAndApprove(address(weth), alice, address(amm), 10_000_000 ether);

        uint256 deposited0;
        uint256 deposited1;

        (deposit0, deposit1, fee0, fee1) =
            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        deposited0 += deposit0;
        deposited1 += deposit1;

        dynamicParams.tickLower -= 20;
        dynamicParams.tickUpper -= 20;

        (deposit0, deposit1, fee0, fee1) =
            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        deposited0 += deposit0;
        deposited1 += deposit1;

        dynamicParams.tickLower += 40;
        dynamicParams.tickUpper += 40;

        (deposit0, deposit1, fee0, fee1) =
            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        deposited0 += deposit0;
        deposited1 += deposit1;
    }

    function _addDynamicLiquidity(
        DynamicLiquidityModificationParams memory dynamicParams,
        LiquidityModificationParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        address provider,
        bytes4 errorSelector
    ) internal returns (uint256 deposit0, uint256 deposit1, uint256 fee0, uint256 fee1) {
        liquidityParams.poolParams = abi.encode(dynamicParams);
        changePrank(provider);
        (deposit0, deposit1, fee0, fee1) = _executeAddLiquidity(liquidityParams, liquidityHooksExtraData, errorSelector);

        if (errorSelector == bytes4(0)) {
            uint160 snapSqrtPriceX96 = dynamicParams.snapSqrtPriceX96;
            (uint256 amount0, uint256 amount1) = _calculateAmountsFromLiquidity(
                liquidityParams.poolId,
                dynamicParams.tickLower,
                dynamicParams.tickUpper,
                uint256(int256(dynamicParams.liquidityChange)),
                true,
                snapSqrtPriceX96
            );
            assertEq(deposit0, amount0, "Deposit0 liquidity mismatch");
            assertEq(deposit1, amount1, "Deposit1 liquidity mismatch");
        }
    }

    function _addDynamicLiquidityNoHookData(
        DynamicLiquidityModificationParams memory dynamicParams,
        LiquidityModificationParams memory liquidityParams,
        address provider,
        bytes4 errorSelector
    ) internal returns (uint256 deposit0, uint256 deposit1, uint256 fee0, uint256 fee1) {
        (deposit0, deposit1, fee0, fee1) = _addDynamicLiquidity(
            dynamicParams, liquidityParams, _emptyLiquidityHooksExtraData(), provider, errorSelector
        );
    }

    function _addStandardDynamicLiquidity(bytes32 poolId)
        internal
        returns (uint256 deposit0, uint256 deposit1, uint256 fee0, uint256 fee1, int24 tickLower, int24 tickUpper)
    {
        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

        tickLower = poolState.tick - (10 * _getPoolTickSpacing(poolId));
        tickLower = _roundToTickSpacing(tickLower, _getPoolTickSpacing(poolId));
        tickUpper = poolState.tick + (10 * _getPoolTickSpacing(poolId));
        tickUpper = _roundToTickSpacing(tickUpper, _getPoolTickSpacing(poolId));

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(tickLower, tickUpper, STANDARD_LIQUIDITY);

        _setupStandardTokenApprovals();

        (deposit0, deposit1, fee0, fee1) =
            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        _setupStandardTokenApprovals();

        (deposit0, deposit1, fee0, fee1) =
            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));
    }

    function _removeDynamicLiquidity(
        DynamicLiquidityModificationParams memory dynamicParams,
        LiquidityModificationParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        address provider,
        bytes4 errorSelector
    ) internal returns (uint256 withdraw0, uint256 withdraw1, uint256 fee0, uint256 fee1) {
        liquidityParams.poolParams = abi.encode(dynamicParams);
        changePrank(provider);
        (withdraw0, withdraw1, fee0, fee1) =
            _executeRemoveLiquidity(liquidityParams, liquidityHooksExtraData, errorSelector);

        if (errorSelector == bytes4(0)) {
            (uint256 amount0, uint256 amount1) = _calculateAmountsFromLiquidity(
                liquidityParams.poolId,
                dynamicParams.tickLower,
                dynamicParams.tickUpper,
                uint256(-int256(dynamicParams.liquidityChange)),
                false
            );

            assertEq(withdraw0, amount0, "Withdraw0 liquidity mismatch");
            assertEq(withdraw1, amount1, "Withdraw1 liquidity mismatch");
        }
    }

    function _removeDynamicLiquidityWithTokensOwed(
        DynamicLiquidityModificationParams memory dynamicParams,
        LiquidityModificationParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        address provider,
        bytes4 errorSelector
    ) internal returns (uint256 withdraw0, uint256 withdraw1, uint256 fee0, uint256 fee1) {
        liquidityParams.poolParams = abi.encode(dynamicParams);
        changePrank(provider);
        (withdraw0, withdraw1, fee0, fee1) =
            _executeRemoveLiquidityWithTokensOwed(liquidityParams, liquidityHooksExtraData, errorSelector);

        if (errorSelector == bytes4(0)) {
            (uint256 amount0, uint256 amount1) = _calculateAmountsFromLiquidity(
                liquidityParams.poolId,
                dynamicParams.tickLower,
                dynamicParams.tickUpper,
                uint256(-int256(dynamicParams.liquidityChange)),
                false
            );

            assertEq(withdraw0, amount0, "Withdraw0 liquidity mismatch");
            assertEq(withdraw1, amount1, "Withdraw1 liquidity mismatch");
        }
    }

    function _calculateAmountsFromLiquidity(
        bytes32 poolId_,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        bool roundUp
    ) internal view returns (uint256 amount0_, uint256 amount1_) {
        return _calculateAmountsFromLiquidity(poolId_, tickLower, tickUpper, liquidity, roundUp, 0);
    }

    function _calculateAmountsFromLiquidity(
        bytes32 poolId_,
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        bool roundUp,
        uint160 snapSqrtPriceX96
    ) internal view returns (uint256 amount0_, uint256 amount1_) {
        int24 tickSpacing = _getPoolTickSpacing(poolId_);
        if (tickLower % tickSpacing != 0 || tickUpper % tickSpacing != 0) {
            revert("Invalid Tick Spacing");
        }
        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId_);

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Current = snapSqrtPriceX96 == 0 ? poolState.sqrtPriceX96 : snapSqrtPriceX96;
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        if (poolState.tick < tickLower) {
            amount1_ = 0;
            uint256 num1 = liquidity << 96;
            uint256 num2 = sqrtUpper - sqrtLower;
            if (roundUp) {
                amount0_ = UnsafeMath.divRoundingUp(FullMath.mulDivRoundingUp(num1, num2, sqrtUpper), sqrtLower);
            } else {
                amount0_ = FullMath.mulDiv(num1, num2, sqrtUpper) / sqrtLower;
            }
        } else if (poolState.tick < tickUpper) {
            uint256 num1 = liquidity << 96;
            uint256 num2 = sqrtUpper - sqrtPriceX96Current;
            if (roundUp) {
                amount0_ =
                    UnsafeMath.divRoundingUp(FullMath.mulDivRoundingUp(num1, num2, sqrtUpper), sqrtPriceX96Current);
            } else {
                amount0_ = FullMath.mulDiv(num1, num2, sqrtUpper) / sqrtPriceX96Current;
            }
            amount1_ = roundUp
                ? FullMath.mulDivRoundingUp(liquidity, (sqrtPriceX96Current - sqrtLower), Q96)
                : FullMath.mulDiv(liquidity, (sqrtPriceX96Current - sqrtLower), Q96);
        } else {
            amount0_ = 0;
            amount1_ = roundUp
                ? FullMath.mulDivRoundingUp(liquidity, (sqrtUpper - sqrtLower), Q96)
                : FullMath.mulDiv(liquidity, (sqrtUpper - sqrtLower), Q96);
        }
    }

    function _poolMaxLiquidityPerTick(bytes32 poolId) internal pure returns (uint128 maxLiquidityPerTick) {
        int24 tickSpacing = _getPoolTickSpacing(poolId);
        int24 minTick = (MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;

        return type(uint128).max / numTicks;
    }

    function _getPoolTickSpacing(bytes32 poolId) internal pure returns (int24) {
        return DynamicPoolDecoder.getPoolTickSpacing(poolId);
    }

    function _calculateDeltaY(uint128 liquidity_, uint160 sqrtP0, int256 deltaX)
        internal
        pure
        returns (int256 deltaY)
    {
        bool zeroForOne = deltaX > 0;

        // numerator: liquidity * sqrtP0 (still in Q96 format)
        uint256 numerator = uint256(liquidity_) * uint256(sqrtP0);

        // denominator: (amountX * sqrtP0) + liquidity * Q96
        int256 denomLeft = deltaX * int256(uint256(sqrtP0)); // Q96 * 1
        int256 denomRight = int256(uint256(liquidity_)) * int256(Q96); // convert to Q96
        int256 denominator = denomLeft + denomRight;

        if (denominator <= 0) {
            denominator = -denominator;
        }

        // Final calculation: sqrtP1 = numerator / denominator in Q96
        uint256 sqrtP1 = FullMath.mulDiv(numerator, Q96, uint256(denominator));

        // deltaY = liquidity * (sqrtP1 - sqrtP0) in Q96
        int256 deltaP = int256(sqrtP1) - int256(int160(sqrtP0));
        bool isDeltaPNegative = deltaP < 0;
        if (isDeltaPNegative) {
            deltaP = -deltaP;
        }

        if (zeroForOne) {
            deltaY = int256(FullMath.mulDiv(liquidity_, uint256(deltaP), Q96));
        } else {
            deltaY = int256(FullMath.mulDivRoundingUp(liquidity_, uint256(deltaP), Q96));
        }

        if (isDeltaPNegative) {
            deltaY = -deltaY;
        }
        return deltaY;
    }

    function _calculateDeltaYWithFees(
        uint128 liquidity_,
        uint160 sqrtP0,
        int256 deltaX,
        uint16 lpFeeBps,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop
    ) internal pure returns (int256 deltaY) {
        if (deltaX > 0) {
            // Calculate the fee amount
            uint256 deltaXAbs = deltaX < 0 ? uint256(-deltaX) : uint256(deltaX);
            uint256 exchangeFeeAmount = FullMath.mulDiv(uint256(exchangeFee.BPS), deltaXAbs, 10_000);

            // Update DeltaX with the fee amount
            deltaXAbs = deltaXAbs - feeOnTop.amount - exchangeFeeAmount;
            deltaX = int256(FullMath.mulDiv(deltaXAbs, 10_000 - lpFeeBps, 10_000));
        }

        deltaY = _calculateDeltaY(liquidity_, sqrtP0, deltaX);

        if (deltaX < 0) {
            uint256 deltaYAbs = deltaY < 0 ? uint256(-deltaY) : uint256(deltaY);
            uint256 lpFeeAmount = FullMath.mulDivRoundingUp(deltaYAbs, lpFeeBps, 10_000 - lpFeeBps);

            deltaYAbs = deltaYAbs + lpFeeAmount + feeOnTop.amount;
            uint256 exchangeFeeAmount = FullMath.mulDiv(uint256(exchangeFee.BPS), deltaYAbs, 10_000 - exchangeFee.BPS);

            deltaYAbs = deltaYAbs + exchangeFeeAmount;
            deltaY = int256(deltaYAbs);
        }
    }

    function _calculateDeltaX(uint128 liquidity_, uint160 sqrtP0, int256 deltaY)
        internal
        pure
        returns (int256 deltaX)
    {
        bool isDeltaYNegative = deltaY < 0;
        if (isDeltaYNegative) {
            deltaY = -deltaY;
        }

        int256 deltaY_X96 = int256(FullMath.mulDivRoundingUp(uint256(deltaY), Q96, uint256(liquidity_)));

        if (isDeltaYNegative) {
            deltaY_X96 = -deltaY_X96;
        }

        // Add deltaY/L to sqrtP0
        uint256 sqrtP1_X96 = uint256(deltaY_X96 + int256(uint256(sqrtP0)));

        // Compute 1/√P0 and 1/√P1 in Q96
        uint256 invSqrtP0 = FullMath.mulDiv(Q96, Q96, sqrtP0);
        uint256 invSqrtP1 = FullMath.mulDiv(Q96, Q96, sqrtP1_X96);

        // Compute Δx = (invSqrtP1 - invSqrtP0) * L / Q96
        // This is because (invSqrtP1 - invSqrtP0) is in Q96, and we multiply by L (Q0)
        if (isDeltaYNegative) {
            deltaX = (invSqrtP1 > invSqrtP0)
                ? int256(FullMath.mulDivRoundingUp((invSqrtP1 - invSqrtP0), liquidity_, Q96))
                : int256(FullMath.mulDivRoundingUp((invSqrtP0 - invSqrtP1), liquidity_, Q96));
            if (deltaX == 0) {
                deltaX = 1;
            }
        } else {
            deltaX = (invSqrtP1 > invSqrtP0)
                ? int256(FullMath.mulDiv((invSqrtP1 - invSqrtP0), liquidity_, Q96))
                : int256(FullMath.mulDiv((invSqrtP0 - invSqrtP1), liquidity_, Q96));
            deltaX = -deltaX;
        }
    }

    function _calculateDeltaXWithFees(
        uint128 liquidity_,
        uint160 sqrtP0,
        int256 deltaY,
        uint16 lpFeeBps,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop
    ) internal pure returns (int256 deltaX) {
        if (deltaY > 0) {
            uint256 deltaYAbs = uint256(deltaY);
            uint256 exchangeFeeAmount = FullMath.mulDiv(uint256(exchangeFee.BPS), deltaYAbs, 10_000);
            deltaYAbs = deltaYAbs - feeOnTop.amount - exchangeFeeAmount;
            deltaY = int256(FullMath.mulDivRoundingUp(deltaYAbs, 10_000 - lpFeeBps, 10_000));
        }

        deltaX = _calculateDeltaX(liquidity_, sqrtP0, deltaY);

        if (deltaY < 0) {
            uint256 deltaXAbs = deltaX < 0 ? uint256(-deltaX) : uint256(deltaX);
            deltaXAbs = deltaXAbs + FullMath.mulDivRoundingUp(deltaXAbs, lpFeeBps, 10_000 - lpFeeBps);
            deltaXAbs = deltaXAbs + feeOnTop.amount;
            uint256 exchangeFeeAmount =
                FullMath.mulDiv(uint256(exchangeFee.BPS), deltaXAbs, 10_000 - uint256(exchangeFee.BPS));
            deltaXAbs = deltaXAbs + exchangeFeeAmount;
            deltaX = deltaX < 0 ? -int256(deltaXAbs) : int256(deltaXAbs);
        }
    }

    function _getPoolFee(bytes32 poolId) internal pure returns (uint16) {
        return DynamicPoolDecoder.getPoolFee(poolId);
    }

    function _calculateAfterSwapFeesSwapByOutput(SwapOrder memory swapOrder, bytes32 poolId_)
        internal
        view
        virtual
        returns (uint256 protocolFees, uint256 tokenInFee)
    {
        TokenSettings memory tokenInSettings = amm.getTokenSettings(swapOrder.tokenIn);
        // HookTokenSettings memory hookSettingsIn = creatorHookSettingsRegistry.getTokenSettings(swapOrder.tokenIn);
        // HookTokenSettings memory hookSettingsOut = creatorHookSettingsRegistry.getTokenSettings(swapOrder.tokenOut);

        uint256 amountIn = swapOrder.limitAmount;

        uint256 minimumProtocolFee;
        if (tokenInSettings.hopFeeBPS > 0) {
            minimumProtocolFee = FullMath.mulDiv(amountIn, tokenInSettings.hopFeeBPS, MAX_BPS);
        }

        // uint256 feeAmount = FullMath.mulDiv(amountIn, hookSettingsIn.inputFeeBPS, MAX_BPS);
        uint256 feeAmount = 0;
        if (feeAmount != 0) {
            amountIn -= feeAmount;
            if (tokenInSettings.hopFeeBPS > 0) {
                protocolFees = FullMath.mulDivRoundingUp(feeAmount, tokenInSettings.hopFeeBPS, MAX_BPS);
            }
            tokenInFee = feeAmount;
        }

        // feeAmount = FullMath.mulDiv(uint256(swapOrder.limitAmount), hookSettingsOut.inputFeeBPS, MAX_BPS);
        feeAmount = 0;
        if (feeAmount != 0) {
            amountIn -= feeAmount;
            if (tokenInSettings.hopFeeBPS > 0) {
                protocolFees += FullMath.mulDivRoundingUp(feeAmount, tokenInSettings.hopFeeBPS, MAX_BPS);
            }
            tokenInFee += feeAmount;
        }

        {
            uint16 poolFeeBPS = _getPoolFee(poolId_);
            uint256 expectedLPFee = FullMath.mulDivRoundingUp(amountIn, poolFeeBPS, MAX_BPS);
            uint256 expectedProtocolFeeFromLP = FullMath.mulDivRoundingUp(
                expectedLPFee, amm.getProtocolFeeStructure(address(0), address(0), bytes32(0)).lpFeeBPS, MAX_BPS
            );

            if (expectedProtocolFeeFromLP + protocolFees < minimumProtocolFee) {
                uint256 shortage = minimumProtocolFee - (expectedProtocolFeeFromLP + protocolFees);
                uint256 protocolFeesFromInput = FullMath.mulDivRoundingUp(
                    shortage,
                    DOUBLE_BPS,
                    (DOUBLE_BPS - poolFeeBPS * amm.getProtocolFeeStructure(address(0), address(0), bytes32(0)).lpFeeBPS)
                );
                amountIn -= protocolFeesFromInput;
                protocolFees += protocolFeesFromInput;
            }
        }
    }

    function _swapByInputSwapDynamicPoolNoExtraData(
        address recipient,
        bytes32 poolId,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        bytes4 errorSelector
    ) internal {
        SwapOrder memory swapOrder =
            _createSwapOrder(recipient, 1000e6, 0, address(usdc), address(weth), block.timestamp + 1);

        SwapHooksExtraData memory swapHooksExtraData;
        bytes memory transferData = bytes("");

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, errorSelector
        );
    }

    function _swapByOutputSwapDynamicPoolNoExtraData(
        address recipient,
        bytes32 poolId,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        bytes4 errorSelector
    ) internal {
        SwapOrder memory swapOrder =
            _createSwapOrder(recipient, -1 ether, type(uint256).max, address(usdc), address(weth), block.timestamp + 1);

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, _emptySwapHooksExtraData(), bytes(""), errorSelector
        );
    }

    function _swapByInputOneForZeroSwapDynamicPoolNoExtraData(
        address recipient,
        bytes32 poolId,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        bytes4 errorSelector
    ) internal {
        SwapOrder memory swapOrder =
            _createSwapOrder(recipient, 10 ether, 0, address(weth), address(usdc), block.timestamp + 1000);

        SwapHooksExtraData memory swapHooksExtraData;
        bytes memory transferData = bytes("");

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, errorSelector
        );
    }

    function _swapByOutputOneForZeroSwapDynamicPoolNoExtraData(
        address recipient,
        bytes32 poolId,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        bytes4 errorSelector
    ) internal {
        SwapOrder memory swapOrder =
            _createSwapOrder(recipient, -100e6, type(uint256).max, address(weth), address(usdc), block.timestamp + 1000);

        SwapHooksExtraData memory swapHooksExtraData;
        bytes memory transferData = bytes("");

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, errorSelector
        );
    }

    function _executeDynamicPoolMultiSwap(
        SwapOrder memory swapOrder,
        bytes32[] memory poolIds,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        SwapHooksExtraData[] memory swapHooksExtraDatas,
        bytes memory transferData,
        bytes4 errorSelector
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        SwapTestCache memory cache;

        _initializeSwapTestCache(poolIds[0], cache, swapOrder, swapHooksExtraDatas[0]);

        ProtocolFeeStructure memory protocolFeeStructure = _getProtocolFeeStructure(poolIds[0], exchangeFee, feeOnTop);

        address tokenIn = swapOrder.tokenIn;
        address tokenOut = swapOrder.tokenOut;

        if (cache.inputSwap) {
            _applyExternalFeesSwapByInput(cache, exchangeFee, feeOnTop, protocolFeeStructure);
            for (uint256 i = 0; i < poolIds.length; i++) {
                protocolFeeStructure = _getProtocolFeeStructure(poolIds[i], exchangeFee, feeOnTop);

                {
                    PoolState memory poolState = LimitBreakAMM(amm).getPoolState(poolIds[i]);
                    cache.poolFeeBPS = _getPoolFee(poolIds[i]);
                    cache.poolId = poolIds[i];
                    poolState.token0 == tokenIn ? tokenOut = poolState.token1 : tokenOut = poolState.token0;
                    cache.zeroForOne = poolState.token0 == tokenIn;
                }
                _applyBeforeSwapHookFeesSwapByInput(cache, swapOrder, protocolFeeStructure);
                _calculateSwapByInputSwap(cache, protocolFeeStructure);
                console2.log("After pool %s, amount out: %s", i, cache.amountUnspecifiedExpected);
                _applyAfterSwapHookFeesSwapByInput(cache, swapOrder);
                cache.amountSpecifiedAbs = cache.amountUnspecifiedExpected;
                tokenIn = tokenOut;
            }
            cache.expectedAmountIn = uint256(swapOrder.amountSpecified);
            cache.expectedAmountOut = cache.amountUnspecifiedExpected;
        } else {
            for (uint256 i = 0; i < poolIds.length; i++) {
                protocolFeeStructure = _getProtocolFeeStructure(poolIds[i], exchangeFee, feeOnTop);

                {
                    PoolState memory poolState = LimitBreakAMM(amm).getPoolState(poolIds[i]);
                    cache.poolFeeBPS = _getPoolFee(poolIds[i]);
                    cache.poolId = poolIds[i];
                    poolState.token0 == tokenIn ? tokenOut = poolState.token1 : tokenOut = poolState.token0;
                    cache.zeroForOne = poolState.token0 == tokenIn;                    
                    console2.log("tokenIn: %s, tokenOut: %s", tokenIn, tokenOut);
                    console2.log("cache.zeroForOne: %s", cache.zeroForOne);
                }
                _applyBeforeSwapHookFeesSwapByOutput(cache, swapOrder);
                _calculateSwapByOutputSwap(cache, protocolFeeStructure);
                console2.log("After pool %s, amount out: %s", i, cache.amountUnspecifiedExpected);
                _applyAfterSwapHookFeesSwapByOutput(cache, swapOrder, protocolFeeStructure);
                cache.amountSpecifiedAbs = cache.amountUnspecifiedExpected;
                tokenOut = tokenIn;
            }
            _applyExternalFeesSwapByOutput(cache, exchangeFee, feeOnTop, protocolFeeStructure);
            cache.expectedAmountIn = cache.amountUnspecifiedExpected;
            cache.expectedAmountOut = uint256(-swapOrder.amountSpecified);
        }

        changePrank(swapOrder.recipient);
        (amountIn, amountOut) =
            _executeMultiSwap(swapOrder, poolIds, exchangeFee, feeOnTop, swapHooksExtraDatas, transferData, bytes4(0));
        if (errorSelector == bytes4(0)) {
            if (swapOrder.amountSpecified > 0) {
                assertEq(amountOut, cache.expectedAmountOut, "Amount out mismatch");
                assertEq(amountIn, cache.expectedAmountIn, "Amount in mismatch");
            } else {
                assertEq(amountIn, cache.expectedAmountIn, "Amount in mismatch");
                assertEq(amountOut, cache.expectedAmountOut, "Amount out mismatch");
            }
        }
    }

    function _generatePoolId(
        PoolCreationDetails memory poolCreationDetails,
        DynamicPoolCreationDetails memory dynamicPoolDetails
    ) internal view returns (bytes32 poolId) {
        poolId = EfficientHash.efficientHash(
            bytes32(uint256(uint160(address(dynamicPool)))),
            bytes32(uint256(poolCreationDetails.fee)),
            bytes32(uint256(int256(dynamicPoolDetails.tickSpacing))),
            bytes32(uint256(uint160(poolCreationDetails.token0))),
            bytes32(uint256(uint160(poolCreationDetails.token1))),
            bytes32(uint256(uint160(poolCreationDetails.poolHook)))
        ) & POOL_HASH_MASK;

        poolId = poolId | bytes32((uint256(uint160(address(dynamicPool))) << 144))
            | bytes32(uint256(poolCreationDetails.fee) << 0)
            | bytes32(uint256(uint24(dynamicPoolDetails.tickSpacing)) << 16);
    }

    function _initializeSwapTestCache(
        bytes32 poolId,
        SwapTestCache memory cache,
        SwapOrder memory swapOrder,
        SwapHooksExtraData memory swapHooksExtraData
    ) internal view {
        _initializeProtocolFees(cache, swapOrder);

        cache.poolId = poolId;
        cache.poolFeeBPS = _getPoolFee(poolId);
        cache.inputSwap = swapOrder.amountSpecified > 0;
        cache.zeroForOne = swapOrder.tokenIn < swapOrder.tokenOut;

        if (cache.inputSwap) {
            cache.expectedAmountIn = cache.amountSpecifiedAbs = uint256(swapOrder.amountSpecified);
        } else {
            cache.expectedAmountOut = cache.amountSpecifiedAbs = uint256(-swapOrder.amountSpecified);
        }

        if (swapHooksExtraData.poolType.length == 32) {
            cache.sqrtPriceLimitX96 = abi.decode(swapHooksExtraData.poolType, (uint160));
        } else {
            cache.zeroForOne
                ? cache.sqrtPriceLimitX96 = MIN_SQRT_RATIO + 1
                : cache.sqrtPriceLimitX96 = MAX_SQRT_RATIO - 1;
        }
    }

    function _executeDynamicPoolSingleSwap(
        SwapOrder memory swapOrder,
        bytes32 poolId,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        SwapHooksExtraData memory swapHooksExtraData,
        bytes memory transferData,
        bytes4 errorSelector
    ) internal virtual returns (uint256 amountIn, uint256 amountOut) {
        SwapTestCache memory cache;
        _initializeSwapTestCache(poolId, cache, swapOrder, swapHooksExtraData);

        ProtocolFeeStructure memory protocolFeeStructure = _getProtocolFeeStructure(poolId, exchangeFee, feeOnTop);

        if (errorSelector == bytes4(0)) {
            {
                if (cache.inputSwap) {
                    uint256 amountInOriginal = cache.amountSpecifiedAbs;
                    _applyBeforeSwapFeesSwapByInput(cache, swapOrder, exchangeFee, feeOnTop, protocolFeeStructure);
                    _calculateSwapByInputSwap(cache, protocolFeeStructure);
                    _applyAfterSwapFeesSwapByInput(cache, swapOrder);
                    cache.expectedAmountOut = cache.amountUnspecifiedExpected;
                    cache.expectedAmountIn = amountInOriginal - cache.amountSpecifiedAbs;
                } else {
                    uint256 amountOutOriginal = cache.amountSpecifiedAbs;
                    _applyBeforeSwapFeesSwapByOutput(cache, swapOrder);
                    uint256 amountOutDiff = cache.amountSpecifiedAbs - amountOutOriginal;
                    _calculateSwapByOutputSwap(cache, protocolFeeStructure);
                    _applyAfterSwapFeesSwapByOutputWithHopFees(cache, swapOrder, exchangeFee, feeOnTop, protocolFeeStructure);
                    cache.expectedAmountOut = cache.amountSpecifiedAbs - amountOutDiff;
                    cache.expectedAmountIn = cache.amountUnspecifiedExpected;
                }

                (amountIn, amountOut) = _executeSingleSwap(
                    swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, errorSelector
                );

                assertEq(amountIn, cache.expectedAmountIn, "Dynamic Swap: Amount in mismatch");
                assertEq(amountOut, cache.expectedAmountOut, "Dynamic Swap: Amount out mismatch");

                _verifyProtocolFees(swapOrder, cache);
            }
        } else {
            (amountIn, amountOut) = _executeSingleSwap(
                swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, errorSelector
            );
        }
    }

    function _calculateSwapByInputSwap(SwapTestCache memory cache, ProtocolFeeStructure memory protocolFeeStructure)
        internal
        view
    {
        bytes32 poolId = cache.poolId;
        bool zeroForOne = cache.zeroForOne;
        uint256 amountSpecified = cache.amountSpecifiedAbs;
        uint256 poolFeeBPS = cache.poolFeeBPS;
        uint256 protocolFeeBPS = protocolFeeStructure.lpFeeBPS;
        uint160 sqrtPriceLimitX96 = cache.sqrtPriceLimitX96;
        console2.log("amountSpecified: %s", amountSpecified);

        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

        DynamicSwapCache memory swapCache = DynamicSwapCache({
            poolId: poolId,
            zeroForOne: zeroForOne,
            liquidity: poolState.liquidity,
            tick: poolState.tick,
            amountSpecified: amountSpecified,
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            protocolFeeBPS: uint16(protocolFeeBPS),
            protocolFee: 0,
            feeAmount: 0,
            feeGrowthGlobalX128: 0,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            sqrtPriceCurrentX96: poolState.sqrtPriceX96
        });

        if (swapCache.zeroForOne) {
            swapCache.feeGrowthGlobalX128 = poolState.feeGrowthGlobal0X128;
        } else {
            swapCache.feeGrowthGlobalX128 = poolState.feeGrowthGlobal1X128;
        }

        _computeSwap(swapCache, uint16(poolFeeBPS), true);

        cache.amountSpecifiedAbs = swapCache.amountSpecifiedRemaining;
        cache.amountUnspecifiedExpected = swapCache.amountCalculated;

        if (zeroForOne) {
            cache.expectedProtocolFees0 += swapCache.protocolFee;
        } else {
            cache.expectedProtocolFees1 += swapCache.protocolFee;
        }
    }

    function _calculateSwapByOutputSwap(SwapTestCache memory cache, ProtocolFeeStructure memory protocolFeeStructure)
        internal
        view
    {
        bytes32 poolId = cache.poolId;
        bool zeroForOne = cache.zeroForOne;
        uint256 amountSpecified = cache.amountSpecifiedAbs;
        uint256 poolFeeBPS = cache.poolFeeBPS;
        uint256 protocolFeeBPS = protocolFeeStructure.lpFeeBPS;
        uint160 sqrtPriceLimitX96 = cache.sqrtPriceLimitX96;

        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

        DynamicSwapCache memory swapCache = DynamicSwapCache({
            poolId: poolId,
            zeroForOne: zeroForOne,
            liquidity: poolState.liquidity,
            tick: poolState.tick,
            amountSpecified: amountSpecified,
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            protocolFeeBPS: protocolFeeBPS,
            protocolFee: 0,
            feeAmount: 0,
            feeGrowthGlobalX128: 0,
            sqrtPriceLimitX96: sqrtPriceLimitX96,
            sqrtPriceCurrentX96: poolState.sqrtPriceX96
        });

        if (swapCache.zeroForOne) {
            swapCache.feeGrowthGlobalX128 = poolState.feeGrowthGlobal0X128;
        } else {
            swapCache.feeGrowthGlobalX128 = poolState.feeGrowthGlobal1X128;
        }

        _computeSwap(swapCache, uint16(poolFeeBPS), false);

        cache.amountSpecifiedAbs -= swapCache.amountSpecifiedRemaining;
        cache.amountUnspecifiedExpected = swapCache.amountCalculated;
        if (zeroForOne) {
            cache.expectedProtocolFees0 += swapCache.protocolFee;
        } else {
            cache.expectedProtocolFees1 += swapCache.protocolFee;
        }
    }

    function _computeSwap(DynamicSwapCache memory swapCache, uint16 poolFeeBPS, bool inputSwap) internal view {
        bool zeroForOne = swapCache.zeroForOne;
        bytes32 poolId = swapCache.poolId;
        int24 tickSpacing = _getPoolTickSpacing(poolId);
        // Get all active ticks for the pool
        (int24[] memory ticks, TickInfo[] memory tickInfos) = _getLiquidityAcrossAllTicks(poolId, tickSpacing);

        // Perform the swap simulation
        StepComputations memory step;
        uint256 loopCount;
        while (swapCache.amountSpecifiedRemaining != 0 && swapCache.sqrtPriceCurrentX96 != swapCache.sqrtPriceLimitX96)
        {
            step.sqrtPriceStartX96 = swapCache.sqrtPriceCurrentX96;

            // Find next tick to cross
            (step.tickNext, step.initialized) =
                _nextInitializedTickWithinOneWord(ticks, swapCache.tick, tickSpacing, zeroForOne);

            if (step.tickNext < MIN_TICK) {
                step.tickNext = MIN_TICK;
            } else if (step.tickNext > MAX_TICK) {
                step.tickNext = MAX_TICK;
            }

            // Calculate sqrt price at next tick
            step.sqrtPriceNextX96 = TickMath.getSqrtPriceAtTick(step.tickNext);
            step.sqrtPriceNextX96 = swapCache.zeroForOne
                ? (
                    step.sqrtPriceNextX96 < swapCache.sqrtPriceLimitX96
                        ? swapCache.sqrtPriceLimitX96
                        : step.sqrtPriceNextX96
                )
                : (
                    step.sqrtPriceNextX96 > swapCache.sqrtPriceLimitX96
                        ? swapCache.sqrtPriceLimitX96
                        : step.sqrtPriceNextX96
                );

            // Calculate swap step within current liquidity range
            _computeSwapStep(swapCache, step, poolFeeBPS, inputSwap);

            if (swapCache.protocolFeeBPS > 0) {
                uint256 delta = FullMath.mulDivRoundingUp(step.feeAmount, swapCache.protocolFeeBPS, MAX_BPS);
                step.feeAmount -= delta;
                swapCache.protocolFee += uint128(delta);
            }

            swapCache.feeAmount = swapCache.feeAmount + step.feeAmount;

            if (swapCache.liquidity > 0) {
                unchecked {
                    swapCache.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, Q128, swapCache.liquidity);
                }
            }

            if (swapCache.sqrtPriceCurrentX96 == step.sqrtPriceNextX96) {
                // if the tick is initialized, run the tick transition
                if (step.initialized) {
                    int128 liquidityNet = _getLiquidityNetAtTick(ticks, tickInfos, step.tickNext);
                    // if we're moving leftward, we interpret liquidityNet as the opposite sign
                    // safe because liquidityNet cannot be type(int128).min
                    if (swapCache.zeroForOne) liquidityNet = -liquidityNet;
                    swapCache.liquidity = LiquidityMath.addDelta(swapCache.liquidity, liquidityNet);
                }

                swapCache.tick = swapCache.zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (swapCache.sqrtPriceCurrentX96 != step.sqrtPriceStartX96) {
                // recompute unless we're on a lower tick boundary (i.e. already transitioned ticks), and haven't moved
                swapCache.tick = TickMath.getTickAtSqrtPrice(swapCache.sqrtPriceCurrentX96);
            }

            loopCount++;
            if (loopCount > 10_000) {
                console2.log("Infinite loop detected in swap computation, breaking out after 10000 iterations");
                break;
            }
        }
    }

    function _computeSwapStep(
        DynamicSwapCache memory swapCache,
        StepComputations memory step,
        uint16 poolFeeBPS,
        bool inputSwap
    ) internal pure {
        if (inputSwap) {
            _computeSwapStepSwapByInput(swapCache, step, poolFeeBPS);
        } else {
            _computeSwapStepSwapByOutput(swapCache, step, poolFeeBPS);
        }
    }

    function _computeSwapStepSwapByInput(
        DynamicSwapCache memory swapCache,
        StepComputations memory step,
        uint16 poolFeeBPS
    ) internal pure {
        uint160 sqrtPriceTargetX96 = step.sqrtPriceNextX96;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;

        bool zeroForOne = swapCache.zeroForOne;
        uint128 liquidity = swapCache.liquidity;
        uint160 sqrtPriceCurrentX96 = swapCache.sqrtPriceCurrentX96;
        uint256 amountRemaining = swapCache.amountSpecifiedRemaining;

        uint256 amountRemainingLessFee = FullMath.mulDiv(amountRemaining, MAX_BPS - poolFeeBPS, MAX_BPS);
        amountIn = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, true)
            : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, true);
        if (amountRemainingLessFee >= amountIn) {
            // `amountIn` is capped by the target price
            sqrtPriceNextX96 = sqrtPriceTargetX96;
            feeAmount = poolFeeBPS == MAX_BPS
                ? amountIn // amountIn is always 0 here, as amountRemainingLessFee == 0 and amountRemainingLessFee >= amountIn
                : FullMath.mulDivRoundingUp(amountIn, poolFeeBPS, MAX_BPS - poolFeeBPS);
        } else {
            // exhaust the remaining amount
            amountIn = amountRemainingLessFee;
            sqrtPriceNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceCurrentX96, liquidity, amountRemainingLessFee, zeroForOne
            );
            // we didn't reach the target, so take the remainder of the maximum input as fee
            feeAmount = amountRemaining - amountIn;
        }
        amountOut = zeroForOne
            ? SqrtPriceMath.getAmount1Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, false)
            : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);

        swapCache.sqrtPriceCurrentX96 = sqrtPriceNextX96;
        step.amountIn = amountIn;
        step.amountOut = amountOut;
        step.feeAmount = feeAmount;

        swapCache.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount);
        swapCache.amountCalculated = swapCache.amountCalculated + step.amountOut;
    }

    function _computeSwapStepSwapByOutput(
        DynamicSwapCache memory swapCache,
        StepComputations memory step,
        uint16 poolFeeBPS
    ) internal pure {
        uint160 sqrtPriceTargetX96 = step.sqrtPriceNextX96;
        uint160 sqrtPriceNextX96;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;

        bool zeroForOne = swapCache.zeroForOne;
        uint128 liquidity = swapCache.liquidity;
        uint160 sqrtPriceCurrentX96 = swapCache.sqrtPriceCurrentX96;
        uint256 amountRemaining = swapCache.amountSpecifiedRemaining;

        amountOut = zeroForOne
            ? SqrtPriceMath.getAmount1Delta(sqrtPriceTargetX96, sqrtPriceCurrentX96, liquidity, false)
            : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, false);
        if (uint256(amountRemaining) >= amountOut) {
            // `amountOut` is capped by the target price
            sqrtPriceNextX96 = sqrtPriceTargetX96;
        } else {
            // cap the output amount to not exceed the remaining output amount
            amountOut = uint256(amountRemaining);
            sqrtPriceNextX96 =
                SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtPriceCurrentX96, liquidity, amountOut, zeroForOne);
        }
        amountIn = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(sqrtPriceNextX96, sqrtPriceCurrentX96, liquidity, true)
            : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);

        feeAmount = FullMath.mulDivRoundingUp(amountIn, poolFeeBPS, MAX_BPS - poolFeeBPS);

        swapCache.sqrtPriceCurrentX96 = sqrtPriceNextX96;
        step.amountIn = amountIn;
        step.amountOut = amountOut;
        step.feeAmount = feeAmount;

        swapCache.amountSpecifiedRemaining -= step.amountOut;
        swapCache.amountCalculated = swapCache.amountCalculated + (step.amountIn + step.feeAmount);
    }

    function _getLiquidityNetAtTick(int24[] memory ticks, TickInfo[] memory tickInfos, int24 tick)
        internal
        pure
        returns (int128)
    {
        for (uint256 i = 0; i < ticks.length; i++) {
            if (ticks[i] == tick) {
                return tickInfos[i].liquidityNet;
            }
        }
        return 0;
    }

    function _getTargetTick(uint256 amountRemaining, uint128 liquidity, uint160 sqrtPriceX96, bool zeroForOne)
        internal
        pure
        returns (int24)
    {
        if (liquidity == 0) {
            return TickMath.getTickAtSqrtPrice(sqrtPriceX96);
        }

        uint160 targetSqrtPrice;

        if (zeroForOne) {
            // Swapping token0 for token1 (deltaX > 0)
            // Calculate what the sqrt price would be after consuming all remaining amount
            int256 deltaX = int256(amountRemaining);
            targetSqrtPrice = _calculateNewSqrtPrice(sqrtPriceX96, liquidity, deltaX);
        } else {
            // Swapping token1 for token0 (deltaY > 0)
            // Calculate what the sqrt price would be after consuming all remaining amount
            int256 deltaY = int256(amountRemaining);
            targetSqrtPrice = _calculateNewSqrtPriceFromDeltaY(sqrtPriceX96, liquidity, deltaY);
        }

        return TickMath.getTickAtSqrtPrice(targetSqrtPrice);
    }

    function _calculateNewSqrtPriceFromDeltaY(uint160 sqrtP0, uint128 liquidity, int256 deltaY)
        internal
        pure
        returns (uint160)
    {
        // From your deltaX calculation: sqrtP1 = sqrtP0 + deltaY/L
        int256 deltaY_X96 = int256(FullMath.mulDiv(uint256(deltaY > 0 ? deltaY : -deltaY), Q96, uint256(liquidity)));

        if (deltaY < 0) {
            deltaY_X96 = -deltaY_X96;
        }

        return uint160(uint256(deltaY_X96 + int256(uint256(sqrtP0))));
    }

    function _calculateNewSqrtPrice(uint160 sqrtP0, uint128 liquidity, int256 deltaX) internal pure returns (uint160) {
        // From your deltaY calculation, we can derive:
        // sqrtP1 = (liquidity * sqrtP0) / (deltaX * sqrtP0 + liquidity * Q96)

        uint256 numerator = uint256(liquidity) * uint256(sqrtP0);
        int256 denomLeft = deltaX * int256(uint256(sqrtP0));
        int256 denomRight = int256(uint256(liquidity)) * int256(Q96);
        int256 denominator = denomLeft + denomRight;

        if (denominator <= 0) {
            denominator = -denominator;
        }

        return uint160(FullMath.mulDiv(numerator, Q96, uint256(denominator)));
    }

    function _nextInitializedTickWithinOneWord(int24[] memory ticks, int24 tick, int24 tickSpacing, bool lte)
        internal
        pure
        returns (int24 next, bool initialized)
    {
        if (lte) {
            // Search for highest tick <= current tick
            for (int256 i = int256(ticks.length) - 1; i >= 0; i--) {
                if (ticks[uint256(i)] <= tick) {
                    return (ticks[uint256(i)], true);
                }
            }
            return (_roundToTickSpacing(MIN_TICK, tickSpacing), false);
        } else {
            // Search for lowest tick > current tick
            for (uint256 i = 0; i < ticks.length; i++) {
                if (ticks[i] > tick) {
                    return (ticks[i], true);
                }
            }
            return (_roundToTickSpacing(MAX_TICK, tickSpacing), false);
        }
    }

    function _getLiquidityAcrossAllTicks(bytes32 poolId, int24 tickSpacing)
        internal
        view
        returns (int24[] memory ticks, TickInfo[] memory tickInfos)
    {
        // Calculate the total number of possible ticks
        int24 minTick = _roundToTickSpacing(MIN_TICK, tickSpacing);
        int24 maxTick = _roundToTickSpacing(MAX_TICK, tickSpacing);
        uint256 maxPossibleTicks = uint256(uint24((maxTick - minTick) / tickSpacing)) + 1;

        // Create temporary arrays with max possible size
        int24[] memory tempTicks = new int24[](maxPossibleTicks);
        TickInfo[] memory tempTickInfos = new TickInfo[](maxPossibleTicks);

        uint256 count = 0;
        int24 tick = minTick;

        while (tick <= maxTick) {
            TickInfo memory tickInfo = dynamicPool.getTickInfo(address(amm), poolId, tick);
            if (tickInfo.initialized) {
                tempTicks[count] = tick;
                tempTickInfos[count] = tickInfo;
                count++;
            }

            tick += tickSpacing;
        }

        ticks = new int24[](count);
        tickInfos = new TickInfo[](count);

        for (uint256 i = 0; i < count; i++) {
            ticks[i] = tempTicks[i];
            tickInfos[i] = tempTickInfos[i];
        }
    }

    function _roundToTickSpacing(int24 tick, int24 tickSpacing) internal pure returns (int24) {
        int24 remainder = tick % tickSpacing;
        if (remainder > 0) {
            tick -= remainder;
        } else if (remainder < 0) {
            tick -= remainder;
        }
        return tick;
    }

    function _applyAfterSwapFeesSwapByOutputWithHopFees(
        SwapTestCache memory cache,
        SwapOrder memory swapOrder,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        ProtocolFeeStructure memory protocolFeeStructure
    ) internal virtual {
        _applyAfterSwapHookFeesSwapByOutputWithHopFees(cache, swapOrder, protocolFeeStructure);
        _applyExternalFeesSwapByOutput(cache, exchangeFee, feeOnTop, protocolFeeStructure);
    }

    function _applyAfterSwapHookFeesSwapByOutputWithHopFees(
        SwapTestCache memory cache,
        SwapOrder memory swapOrder,
        ProtocolFeeStructure memory protocolFeeStructure
    ) internal view {
        TokenSettings memory tokenInSettings = amm.getTokenSettings(swapOrder.tokenIn);
        TokenSettings memory tokenOutSettings = amm.getTokenSettings(swapOrder.tokenOut);

        uint256 tokenInFee;
        {
            if (tokenInSettings.tokenHook != address(0)) {
                tokenInFee =
                    _calculateHookFeeAfterSwapSwapByOutput(cache.amountUnspecifiedExpected, swapOrder, swapOrder.tokenIn);
            }
            if (tokenOutSettings.tokenHook != address(0)) {
                tokenInFee += _calculateHookFeeAfterSwapSwapByOutput(
                    cache.amountUnspecifiedExpected, swapOrder, swapOrder.tokenOut
                );
            }
        }

        uint256 protocolFee;
        uint256 minimumProtocolFee;

        {
            if (tokenInSettings.hopFeeBPS > 0) {
                minimumProtocolFee =
                    FullMath.mulDiv(cache.amountUnspecifiedExpected, tokenInSettings.hopFeeBPS, MAX_BPS);
            }

            if (tokenInFee != 0) {
                cache.amountUnspecifiedExpected += tokenInFee;
                if (tokenInSettings.hopFeeBPS > 0) {
                    protocolFee = FullMath.mulDiv(tokenInFee, tokenInSettings.hopFeeBPS, MAX_BPS);
                }
            }
        }

        {
            uint16 poolFeeBPS = cache.poolFeeBPS;
            uint256 protocolFeesFromLP = cache.zeroForOne ? cache.expectedProtocolFees0 : cache.expectedProtocolFees0;

            if (protocolFeesFromLP + protocolFee < minimumProtocolFee) {
                uint256 shortage = minimumProtocolFee - protocolFeesFromLP - protocolFee;
                uint256 protocolFeesFromInput = FullMath.mulDivRoundingUp(
                    shortage, MAX_BPS, (MAX_BPS - tokenInSettings.hopFeeBPS)
                );
                cache.amountUnspecifiedExpected += protocolFeesFromInput;
                protocolFee += protocolFeesFromInput;
            }
        }

        if (cache.zeroForOne) {
            cache.expectedProtocolFees0 += protocolFee;
        } else {
            cache.expectedProtocolFees1 += protocolFee;
        }
    }
}
