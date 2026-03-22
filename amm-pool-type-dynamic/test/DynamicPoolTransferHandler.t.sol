pragma solidity ^0.8.24;

import "./DynamicPool.t.sol";
import "@limitbreak/lb-amm-hooks-and-handlers/test/handlers/clob/ClobTransferHandler.t.sol";
import "@limitbreak/lb-amm-hooks-and-handlers/test/handlers/permit/PermitTransferHandler.t.sol";

contract DynamicPoolTransferHandlerTest is DynamicPoolTest, ClobTransferHandlerTest, PermitTransferHandlerTest {
    function setUp() public virtual override(DynamicPoolTest, ClobTransferHandlerTest, PermitTransferHandlerTest) {
        super.setUp();
    }

    function test_singleSwap_withClobTransferHandler() public {
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint256 maxOutputSlippage = 1 ether;
        {
            _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
            _depositToken(bob, address(token0), 1000 ether, bytes4(0));

            uint160 sqrtPriceX96 = _calculatePriceLimit(1, 1000);
            uint256 orderAmount = 1 ether;
            uint160 informationSqrtPriceX96 = 0;
            HooksExtraData memory hooksExtraData =
                HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});


            _openOrder(
                bob,
                address(token0),
                address(token1),
                sqrtPriceX96,
                orderAmount,
                groupKey,
                informationSqrtPriceX96,
                hooksExtraData,
                bytes4(0)
            );
        }

        bytes32 poolId = _createDynamicPoolNoHookData(
            PoolCreationDetails({
                poolType: address(dynamicPool),
                fee: 500,
                token0: address(token0),
                token1: address(token1),
                poolHook: address(0),
                poolParams: bytes("")
            }),
            10,
            792_281_625_142_643_375_935_439_503_360,
            bytes4(0)
        );

        DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

        int24 tickLower = poolState.tick - (10 * _getPoolTickSpacing(poolId));
        tickLower = _roundToTickSpacing(tickLower, _getPoolTickSpacing(poolId));
        int24 tickUpper = poolState.tick + (10 * _getPoolTickSpacing(poolId));
        tickUpper = _roundToTickSpacing(tickUpper, _getPoolTickSpacing(poolId));

        LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

        DynamicLiquidityModificationParams memory dynamicParams =
            _initDynamicLiqParams(tickLower, tickUpper, STANDARD_LIQUIDITY);

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        SwapOrder memory swapOrder =
            _createSwapOrder(address(clob), 1000e6, 0, address(token0), address(token1), block.timestamp + 1);

        SwapHooksExtraData memory swapHooksExtraData;

        bytes memory transferData = bytes.concat(
            abi.encode(address(clob)),
            abi.encode(FillParams({groupKey: groupKey, maxOutputSlippage: maxOutputSlippage, hookData: bytes("")}))
        );

        changePrank(alice);
        _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );
    }

    function _initializeFillOrKillPermitData() internal view returns (FillOrKillPermitTransfer memory) {
        uint256 minAmountOut = 1000e6;
        int256 amountSpecified = 2000e6;
        uint256 deadline = block.timestamp + 1000;
        address recipient = address(alice);
        address tokenIn = address(token0);
        address tokenOut = address(token1);
        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient(address(0), 0);
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient(address(0), 0);
        FillOrKillPermitTransfer memory permitData = FillOrKillPermitTransfer({
            permitProcessor: address(transferValidator),
            from: alice,
            nonce: 0,
            permitAmount: uint256(amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: type(uint256).max,
            cosignature: bytes(""),
            hook: address(0),
            hookData: bytes("")
        });

        permitData.signature = _getSignature(
            aliceKey,
            deadline,
            tokenIn,
            recipient,
            amountSpecified,
            minAmountOut,
            tokenOut,
            exchangeFee,
            feeOnTop,
            permitData
        );

        return permitData;
    }

    function test_singleSwap_withPermitTransferHandler() public {
        _registerTypeHashes();

        FillOrKillPermitTransfer memory permitData = _initializeFillOrKillPermitData();

        _mintAndApprove(address(token0), alice, address(transferValidator), uint256(1000 ether));

        bytes32 poolId = _createDynamicPoolNoHookData(
            PoolCreationDetails({
                poolType: address(dynamicPool),
                fee: 500,
                token0: address(token0),
                token1: address(token1),
                poolHook: address(0),
                poolParams: bytes("")
            }),
            10,
            _calculatePriceLimit(1, 1),
            bytes4(0)
        );

        {
            DynamicPoolState memory poolState = dynamicPool.getPoolState(address(amm), poolId);

            int24 tickLower = poolState.tick - (10 * _getPoolTickSpacing(poolId));
            tickLower = _roundToTickSpacing(tickLower, _getPoolTickSpacing(poolId));
            int24 tickUpper = poolState.tick + (10 * _getPoolTickSpacing(poolId));
            tickUpper = _roundToTickSpacing(tickUpper, _getPoolTickSpacing(poolId));

            LiquidityModificationParams memory liquidityParams = _standardLiquidityModificationParams(poolId);

            DynamicLiquidityModificationParams memory dynamicParams =
                _initDynamicLiqParams(tickLower, tickUpper, STANDARD_LIQUIDITY);

            _mintAndApprove(address(token0), bob, address(amm), 1000 ether);
            _mintAndApprove(address(token1), bob, address(amm), 1000 ether);

            _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, bob, bytes4(0));
        }

        SwapOrder memory swapOrder =
            _createSwapOrder(address(alice), 2000e6, 1000e6, address(token0), address(token1), block.timestamp + 1);

        SwapHooksExtraData memory swapHooksExtraData;

        bytes memory transferData =
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData));

        BPSFeeWithRecipient memory exchangeFee;
        FlatFeeWithRecipient memory feeOnTop;

        uint256 ammBalanceBefore0 = token0.balanceOf(address(amm));
        uint256 aliceBalanceBefore1 = token1.balanceOf(alice);

        changePrank(bob);
        _executeDynamicPoolSingleSwap(
            swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData, bytes4(0)
        );

        uint256 ammBalanceAfter0 = token0.balanceOf(address(amm));
        uint256 aliceBalanceAfter1 = token1.balanceOf(alice);

        assertEq(ammBalanceAfter0 - ammBalanceBefore0, 2000e6);
        assertEq(aliceBalanceAfter1 - aliceBalanceBefore1, (2000e6 * 95 / 100) - 1); //5% LP fee is rounded up, so we are subtracting 1 wei from expected amount
    }
}
