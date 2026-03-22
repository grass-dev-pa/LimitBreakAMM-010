pragma solidity ^0.8.24;

import "./LBAMMCoreBase.t.sol";

contract LBAMMCorePoolBaseTest is LBAMMCoreBaseTest {
    struct HookFees {
        uint256 hookFee0;
        uint256 hookFee1;
        uint256 expectedHookFee0;
        uint256 expectedHookFee1;
    }

    struct ProtocolFees {
        uint256 protocolFees0;
        uint256 protocolFees1;
        uint256 expectedProtocolFees0;
        uint256 expectedProtocolFees1;
    }

    struct SwapTestCache {
        uint16 poolFeeBPS;
        uint256 amountUnspecifiedExpected;
        uint256 amountSpecifiedAbs;
        uint256 exchangeFeeAmount;
        uint256 protocolFees0;
        uint256 protocolFees1;
        uint256 expectedProtocolFees0;
        uint256 expectedProtocolFees1;
        bool zeroForOne;
        bool inputSwap;
        address tokenIn;
        address tokenOut;
        bytes32 poolId;
        uint160 sqrtPriceCurrentX96;
        uint160 sqrtPriceLimitX96;
        uint256 reserveOut;
        uint256 expectedAmountIn;
        uint256 expectedAmountOut;
        uint256 allowedLPFeeDeviation0;
        uint256 allowedLPFeeDeviation1;
        uint256 allowedProtocolFeeDeviation0;
        uint256 allowedProtocolFeeDeviation1;
    }

    function setUp() public virtual override {
        super.setUp();
    }

    function _emptySwapHooksExtraData() internal pure returns (SwapHooksExtraData memory extraData) {}
    function _emptyLiquidityHooksExtraData() internal pure returns (LiquidityHooksExtraData memory extraData) {}

    function _executeSingleSwap(
        SwapOrder memory swapOrder,
        bytes32 poolId,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        SwapHooksExtraData memory swapHooksExtraData,
        bytes memory transferData,
        bytes4 errorSelector
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        (,address msgSender,) = vm.readCallers();
        uint256 balanceBeforeRecipientOut = IERC20(swapOrder.tokenOut).balanceOf(swapOrder.recipient);
        uint256 balanceBeforeExecutorOut = IERC20(swapOrder.tokenOut).balanceOf(msgSender);

        if (errorSelector != bytes4(0)) {
            if (errorSelector == bytes4(PANIC_SELECTOR)) {
                vm.expectRevert();
            } else {
                vm.expectRevert(errorSelector);
            }
        }
        (amountIn, amountOut) =
            amm.singleSwap{gas: 100_000_000}(swapOrder, poolId, exchangeFee, feeOnTop, swapHooksExtraData, transferData);

        if (errorSelector == bytes4(0)) {
            uint256 balanceAfterRecipientOut = IERC20(swapOrder.tokenOut).balanceOf(swapOrder.recipient);
            uint256 balanceAfterExecutorOut = IERC20(swapOrder.tokenOut).balanceOf(msgSender);
            uint256 diff;
            if (swapOrder.recipient != msgSender) {
                diff = (balanceAfterRecipientOut + balanceAfterExecutorOut) - (balanceBeforeRecipientOut + balanceBeforeExecutorOut);
            } else {
                diff = balanceAfterRecipientOut - balanceBeforeRecipientOut;
            }
            assertEq(diff, amountOut, "SingleSwap: TokenOut balance mismatch");
        }
    }

    function _executeMultiSwap(
        SwapOrder memory swapOrder,
        bytes32[] memory poolIds,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        SwapHooksExtraData[] memory swapHooksExtraDatas,
        bytes memory transferData,
        bytes4 errorSelector
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        uint256 balanceBeforeRecipientOut = IERC20(swapOrder.tokenOut).balanceOf(swapOrder.recipient);

        _handleExpectRevert(errorSelector);
        (amountIn, amountOut) =
            amm.multiSwap(swapOrder, poolIds, exchangeFee, feeOnTop, swapHooksExtraDatas, transferData);

        if (errorSelector == bytes4(0)) {
            uint256 balanceAfterRecipientOut = IERC20(swapOrder.tokenOut).balanceOf(swapOrder.recipient);
            uint256 diff = balanceAfterRecipientOut - balanceBeforeRecipientOut;
            assertEq(diff, amountOut, "MultiSwap: TokenOut balance mismatch");
        }
    }

    function _createPool(
        PoolCreationDetails memory details,
        bytes memory token0HookData,
        bytes memory token1HookData,
        bytes memory poolHookData,
        bytes4 errorSelector
    ) internal returns (bytes32 poolId) {
        (poolId,,) = _createPoolWithAddLiquidity(details, token0HookData, token1HookData, poolHookData, bytes(""), errorSelector);
    }

    function _createPoolWithAddLiquidity(
        PoolCreationDetails memory details,
        bytes memory token0HookData,
        bytes memory token1HookData,
        bytes memory poolHookData,
        bytes memory liquidityData,
        bytes4 errorSelector
    ) internal returns (bytes32 poolId, uint256 deposit0, uint256 deposit1) {
        _handleExpectRevert(errorSelector);
        (poolId, deposit0, deposit1) = amm.createPool(details, token0HookData, token1HookData, poolHookData, liquidityData);

        if (errorSelector == bytes4(0)) {
            PoolState memory poolState = amm.getPoolState(poolId);

            address expectedToken0 = details.token0 < details.token1 ? details.token0 : details.token1;
            address expectedToken1 = details.token0 < details.token1 ? details.token1 : details.token0;
            assertEq(poolState.token0, expectedToken0, "CreatePool: Token0 mismatch");
            assertEq(poolState.token1, expectedToken1, "CreatePool: Token1 mismatch");
            assertEq(poolState.poolHook, details.poolHook, "CreatePool: Pool hook mismatch");
        }
    }

    function _executeDirectSwap(
        SwapOrder memory swapOrder,
        DirectSwapParams memory directSwapParams,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        SwapHooksExtraData memory swapHooksExtraData,
        bytes memory transferData,
        bytes4 errorSelector
    ) internal returns (uint256 amountIn, uint256 amountOut) {
        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        }

        uint256 msgValue;

        if (swapOrder.tokenOut == address(wrappedNative)) {
            msgValue = uint256(directSwapParams.swapAmount);
        }

        (amountIn, amountOut) = amm.directSwap{value: msgValue}(
            swapOrder, directSwapParams, exchangeFee, feeOnTop, swapHooksExtraData, transferData
        );

        if (errorSelector == bytes4(0)) {
        }
    }

    function _executeAddLiquidity(
        LiquidityModificationParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        bytes4 errorSelector
    ) internal returns (uint256 deposit0, uint256 deposit1, uint256 fee0, uint256 fee1) {
        (, address msgSender,) = vm.readCallers();

        PoolState memory state = amm.getPoolState(liquidityParams.poolId);

        uint256 balanceBefore0 = IERC20(state.token0).balanceOf(msgSender);
        uint256 balanceBefore1 = IERC20(state.token1).balanceOf(msgSender);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, false, false);
            emit LiquidityAdded(liquidityParams.poolId, msgSender, 0, 0, 0, 0);
        }

        (deposit0, deposit1, fee0, fee1) = amm.addLiquidity{gas: 100_000_000}(liquidityParams, liquidityHooksExtraData);

        if (errorSelector == bytes4(0)) {
            int256 diff0 = int256(balanceBefore0) - int256(IERC20(state.token0).balanceOf(msgSender));
            int256 diff1 = int256(balanceBefore1) - int256(IERC20(state.token1).balanceOf(msgSender));

            assertEq(diff0, int256(deposit0) - int256(fee0), "AddLiquidity: Token0 deposit mismatch");
            assertEq(diff1, int256(deposit1) - int256(fee1), "AddLiquidity: Token1 deposit mismatch");
        }
    }

    function _executeRemoveLiquidity(
        LiquidityModificationParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        bytes4 errorSelector
    ) internal returns (uint256 withdraw0, uint256 withdraw1, uint256 fee0, uint256 fee1) {
        PoolState memory poolState = amm.getPoolState(liquidityParams.poolId);

        (, address msgSender,) = vm.readCallers();
        uint256 balanceBefore0 = IERC20(poolState.token0).balanceOf(msgSender);
        uint256 balanceBefore1 = IERC20(poolState.token1).balanceOf(msgSender);

        _handleExpectRevert(errorSelector);

        (withdraw0, withdraw1, fee0, fee1) = amm.removeLiquidity(liquidityParams, liquidityHooksExtraData);
        if (errorSelector == bytes4(0)) {
            int256 diff0 = int256(IERC20(poolState.token0).balanceOf(msgSender)) - int256(balanceBefore0);
            int256 diff1 = int256(IERC20(poolState.token1).balanceOf(msgSender)) - int256(balanceBefore1);

            assertEq(diff0, int256(withdraw0) + int256(fee0), "RemoveLiquidity: Token0 withdrawal mismatch");
            assertEq(diff1, int256(withdraw1) + int256(fee1), "RemoveLiquidity: Token1 withdrawal mismatch");
        }
    }

    function _executeRemoveLiquidityWithTokensOwed(
        LiquidityModificationParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        bytes4 errorSelector
    ) internal returns (uint256 withdraw0, uint256 withdraw1, uint256 fee0, uint256 fee1) {
        PoolState memory poolState = amm.getPoolState(liquidityParams.poolId);

        (, address msgSender,) = vm.readCallers();
        uint256 balanceBefore0 = IERC20(poolState.token0).balanceOf(msgSender) + amm.getTokensOwed(msgSender, poolState.token0);
        uint256 balanceBefore1 = IERC20(poolState.token1).balanceOf(msgSender) + amm.getTokensOwed(msgSender, poolState.token1);

        _handleExpectRevert(errorSelector);

        (withdraw0, withdraw1, fee0, fee1) = amm.removeLiquidity(liquidityParams, liquidityHooksExtraData);
        if (errorSelector == bytes4(0)) {
            int256 diff0 = int256(IERC20(poolState.token0).balanceOf(msgSender) + amm.getTokensOwed(msgSender, poolState.token0)) - int256(balanceBefore0);
            int256 diff1 = int256(IERC20(poolState.token1).balanceOf(msgSender) + amm.getTokensOwed(msgSender, poolState.token1)) - int256(balanceBefore1);

            assertEq(diff0, int256(withdraw0) + int256(fee0), "RemoveLiquidity: Token0 withdrawal mismatch");
            assertEq(diff1, int256(withdraw1) + int256(fee1), "RemoveLiquidity: Token1 withdrawal mismatch");
        }
    }

    function _executeCollectFees(
        LiquidityCollectFeesParams memory liquidityParams,
        LiquidityHooksExtraData memory liquidityHooksExtraData,
        bytes4 errorSelector
    ) internal returns (uint256 fees0, uint256 fees1) {
        PoolState memory poolState = amm.getPoolState(liquidityParams.poolId);

        (, address msgSender,) = vm.readCallers();

        uint256 balanceBefore0 = IERC20(poolState.token0).balanceOf(msgSender);
        uint256 balanceBefore1 = IERC20(poolState.token1).balanceOf(msgSender);
        uint256 tokensOwedBefore0 = amm.getTokensOwed(msgSender, poolState.token0);
        uint256 tokensOwedBefore1 = amm.getTokensOwed(msgSender, poolState.token1);

        if (poolState.token0 == address(wrappedNative)) {
            balanceBefore0 = msgSender.balance;
        } else if (poolState.token1 == address(wrappedNative)) {
            balanceBefore1 = msgSender.balance;
        }

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, false, false);
            emit FeesCollected(liquidityParams.poolId, msgSender, 0, 0);
        }

        (fees0, fees1) = amm.collectFees(liquidityParams, liquidityHooksExtraData);

        if (errorSelector == bytes4(0)) {
            int256 diff0 = int256(IERC20(poolState.token0).balanceOf(msgSender)) - int256(balanceBefore0);
            if (poolState.token0 == address(wrappedNative)) {
                diff0 = int256(msgSender.balance) - int256(balanceBefore0);
            }
            int256 diff1 = int256(IERC20(poolState.token1).balanceOf(msgSender)) - int256(balanceBefore1);
            if (poolState.token1 == address(wrappedNative)) {
                diff1 = int256(msgSender.balance) - int256(balanceBefore1);
            }
            int256 diffOwed0 = int256(amm.getTokensOwed(msgSender, poolState.token0)) - int256(tokensOwedBefore0);
            int256 diffOwed1 = int256(amm.getTokensOwed(msgSender, poolState.token1)) - int256(tokensOwedBefore1);

            assertEq(diff0 + diffOwed0, int256(fees0), "CollectFees: Token0 fees mismatch");
            assertEq(diff1 + diffOwed1, int256(fees1), "CollectFees: Token1 fees mismatch");
        }
    }

    function _applyExternalFeesSwapByInput(
        SwapTestCache memory cache,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        ProtocolFeeStructure memory protocolFeeStructure
    ) internal pure {
        cache.exchangeFeeAmount = FullMath.mulDiv(cache.amountSpecifiedAbs - feeOnTop.amount, exchangeFee.BPS, 10_000);
        cache.amountSpecifiedAbs -= (cache.exchangeFeeAmount + feeOnTop.amount);
        if (cache.amountSpecifiedAbs < 0) {
            revert("external fees too high");
        }
        if (protocolFeeStructure.exchangeFeeBPS > 0) {
            uint256 exchangeFeeFee =
                FullMath.mulDiv(cache.exchangeFeeAmount, protocolFeeStructure.exchangeFeeBPS, 10_000);
            if (cache.zeroForOne) {
                cache.expectedProtocolFees0 += exchangeFeeFee;
            } else {
                cache.expectedProtocolFees1 += exchangeFeeFee;
            }
        }
        if (protocolFeeStructure.feeOnTopBPS > 0) {
            uint256 feeOnTopFee = FullMath.mulDiv(feeOnTop.amount, protocolFeeStructure.feeOnTopBPS, 10_000);
            if (cache.zeroForOne) {
                cache.expectedProtocolFees0 += feeOnTopFee;
            } else {
                cache.expectedProtocolFees1 += feeOnTopFee;
            }
        }
    }

    function _applyBeforeSwapHookFeesSwapByInput(
        SwapTestCache memory cache,
        SwapOrder memory swapOrder,
        ProtocolFeeStructure memory protocolFeeStructure
    ) internal virtual {
        TokenSettings memory tokenInSettings = amm.getTokenSettings(swapOrder.tokenIn);
        TokenSettings memory tokenOutSettings = amm.getTokenSettings(swapOrder.tokenOut);
        uint256 tokenInFee;
        {
            if (tokenInSettings.tokenHook != address(0)) {
                tokenInFee =
                    _calculateHookFeeBeforeSwapSwapByInput(cache.amountSpecifiedAbs, swapOrder, swapOrder.tokenIn);
            }
            if (tokenOutSettings.tokenHook != address(0)) {
                tokenInFee +=
                    _calculateHookFeeBeforeSwapSwapByInput(cache.amountSpecifiedAbs, swapOrder, swapOrder.tokenOut);
            }
        }
        uint256 protocolFee;
        uint256 minimumProtocolFee;
        {
            if (tokenInSettings.hopFeeBPS > 0) {
                minimumProtocolFee = FullMath.mulDiv(cache.amountSpecifiedAbs, tokenInSettings.hopFeeBPS, MAX_BPS);
            }

            if (tokenInFee != 0) {
                cache.amountSpecifiedAbs -= tokenInFee;
                if (tokenInSettings.hopFeeBPS > 0) {
                    protocolFee = FullMath.mulDiv(tokenInFee, tokenInSettings.hopFeeBPS, MAX_BPS);
                }
            }
        }

        {
            uint16 poolFeeBPS = cache.poolFeeBPS;
            uint256 expectedLPFee = FullMath.mulDivRoundingUp(cache.amountSpecifiedAbs, poolFeeBPS, MAX_BPS);
            uint256 expectedProtocolFeeFromLP = FullMath.mulDiv(expectedLPFee, protocolFeeStructure.lpFeeBPS, MAX_BPS);

            if (expectedProtocolFeeFromLP + protocolFee < minimumProtocolFee) {
                uint256 shortage = minimumProtocolFee - expectedProtocolFeeFromLP - protocolFee;
                uint256 protocolFeesFromInput = FullMath.mulDivRoundingUp(
                    shortage, DOUBLE_BPS, (DOUBLE_BPS - poolFeeBPS * protocolFeeStructure.lpFeeBPS)
                );
                cache.amountSpecifiedAbs -= protocolFeesFromInput;
                protocolFee += protocolFeesFromInput;
            }
        }

        if (cache.zeroForOne) {
            cache.expectedProtocolFees0 += protocolFee;
        } else {
            cache.expectedProtocolFees1 += protocolFee;
        }
    }

    function _applyBeforeSwapFeesSwapByInput(
        SwapTestCache memory cache,
        SwapOrder memory swapOrder,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        ProtocolFeeStructure memory protocolFeeStructure
    ) internal virtual {
        _applyExternalFeesSwapByInput(cache, exchangeFee, feeOnTop, protocolFeeStructure);
        _applyBeforeSwapHookFeesSwapByInput(cache, swapOrder, protocolFeeStructure);
    }

    function _applyAfterSwapFeesSwapByInput(
        SwapTestCache memory cache,
        SwapOrder memory swapOrder
    ) internal virtual {
        _applyAfterSwapHookFeesSwapByInput(cache, swapOrder);
    }

    function _applyBeforeSwapFeesSwapByOutput(
        SwapTestCache memory cache,
        SwapOrder memory swapOrder
    ) internal virtual {
        _applyBeforeSwapHookFeesSwapByOutput(cache, swapOrder);
    }

    function _applyAfterSwapFeesSwapByOutput(
        SwapTestCache memory cache,
        SwapOrder memory swapOrder,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        ProtocolFeeStructure memory protocolFeeStructure
    ) internal virtual {
        _applyAfterSwapHookFeesSwapByOutput(cache, swapOrder, protocolFeeStructure);
        _applyExternalFeesSwapByOutput(cache, exchangeFee, feeOnTop, protocolFeeStructure);
    }

    function _applyBeforeSwapHookFeesSwapByOutput(
        SwapTestCache memory cache,
        SwapOrder memory swapOrder
    ) internal virtual {
        TokenSettings memory tokenInSettings = amm.getTokenSettings(swapOrder.tokenIn);
        TokenSettings memory tokenOutSettings = amm.getTokenSettings(swapOrder.tokenOut);

        uint256 tokenOutFee;
        {
            if (tokenInSettings.tokenHook != address(0)) {
                tokenOutFee =
                    _calculateHookFeeBeforeSwapSwapByOutput(cache.amountSpecifiedAbs, swapOrder, swapOrder.tokenIn);
            }
            if (tokenOutSettings.tokenHook != address(0)) {
                tokenOutFee +=
                    _calculateHookFeeBeforeSwapSwapByOutput(cache.amountSpecifiedAbs, swapOrder, swapOrder.tokenOut);
            }
        }

        uint256 protocolFee;
        if (tokenOutFee != 0) {
            cache.amountSpecifiedAbs += tokenOutFee;
            if (tokenInSettings.hopFeeBPS > 0) {
                protocolFee = FullMath.mulDiv(tokenOutFee, tokenInSettings.hopFeeBPS, MAX_BPS);
            }
        }

        if (cache.zeroForOne) {
            cache.expectedProtocolFees1 += protocolFee;
        } else {
            cache.expectedProtocolFees0 += protocolFee;
        }
    }

    function _applyExternalFeesSwapByOutput(
        SwapTestCache memory cache,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop,
        ProtocolFeeStructure memory protocolFeeStructure
    ) internal pure {
        cache.exchangeFeeAmount =
            FullMath.mulDivRoundingUp(cache.amountUnspecifiedExpected, exchangeFee.BPS, 10_000 - exchangeFee.BPS);
        cache.amountUnspecifiedExpected += cache.exchangeFeeAmount;
        cache.amountUnspecifiedExpected += feeOnTop.amount;
        if (protocolFeeStructure.exchangeFeeBPS > 0) {
            uint256 exchangeFeeFee =
                FullMath.mulDivRoundingUp(cache.exchangeFeeAmount, protocolFeeStructure.exchangeFeeBPS, 10_000);
            if (cache.zeroForOne) {
                cache.expectedProtocolFees0 += exchangeFeeFee;
            } else {
                cache.expectedProtocolFees1 += exchangeFeeFee;
            }
        }
        if (protocolFeeStructure.feeOnTopBPS > 0) {
            uint256 feeOnTopFee = FullMath.mulDiv(feeOnTop.amount, protocolFeeStructure.feeOnTopBPS, 10_000);
            if (cache.zeroForOne) {
                cache.expectedProtocolFees0 += feeOnTopFee;
            } else {
                cache.expectedProtocolFees1 += feeOnTopFee;
            }
        }
    }

    function _applyAfterSwapHookFeesSwapByInput(SwapTestCache memory cache, SwapOrder memory swapOrder) internal view {
        TokenSettings memory tokenInSettings = amm.getTokenSettings(swapOrder.tokenIn);
        TokenSettings memory tokenOutSettings = amm.getTokenSettings(swapOrder.tokenOut);

        uint256 tokenOutFee;

        if (tokenInSettings.tokenHook != address(0)) {
            tokenOutFee =
                _calculateHookFeeAfterSwapSwapByInput(cache.amountUnspecifiedExpected, swapOrder, swapOrder.tokenIn);
        }
        if (tokenOutSettings.tokenHook != address(0)) {
            tokenOutFee +=
                _calculateHookFeeAfterSwapSwapByInput(cache.amountUnspecifiedExpected, swapOrder, swapOrder.tokenOut);
        }

        uint256 protocolFee;
        if (tokenOutFee != 0) {
            cache.amountUnspecifiedExpected -= tokenOutFee;
            if (tokenOutSettings.hopFeeBPS > 0) {
                protocolFee = FullMath.mulDiv(tokenOutFee, tokenOutSettings.hopFeeBPS, MAX_BPS);
            }
        }

        if (cache.zeroForOne) {
            cache.expectedProtocolFees1 += protocolFee;
        } else {
            cache.expectedProtocolFees0 += protocolFee;
        }
    }

    function _applyAfterSwapHookFeesSwapByOutput(
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

    function _verifyProtocolFees(SwapOrder memory swapOrder, SwapTestCache memory cache) internal view {
        address token0 = swapOrder.tokenIn < swapOrder.tokenOut ? swapOrder.tokenIn : swapOrder.tokenOut;
        address token1 = swapOrder.tokenIn < swapOrder.tokenOut ? swapOrder.tokenOut : swapOrder.tokenIn;

        cache.protocolFees0 = amm.getProtocolFees(token0) - cache.protocolFees0;
        cache.protocolFees1 = amm.getProtocolFees(token1) - cache.protocolFees1;

        assertApproxEqAbs(cache.protocolFees0, cache.expectedProtocolFees0, cache.allowedProtocolFeeDeviation0, "Verify Protocol Fees: Incorrect token0 Fee");
        assertApproxEqAbs(cache.protocolFees1, cache.expectedProtocolFees1, cache.allowedProtocolFeeDeviation1, "Verify Protocol Fees: Incorrect token1 Fee");
    }

    /// @dev Override and implement in the hook test contracts as needed.
    function _calculateHookFeeAfterSwapSwapByInput(uint256, SwapOrder memory, address)
        internal
        view
        virtual
        returns (uint256 feeAmount)
    {
        return 0;
    }

    /// @dev Override and implement in the hook test contracts as needed.
    function _calculateHookFeeBeforeSwapSwapByInput(uint256, SwapOrder memory, address)
        internal
        view
        virtual
        returns (uint256 feeAmount)
    {
        return 0;
    }

    /// @dev Override and implement in the hook test contracts as needed.
    function _calculateHookFeeBeforeSwapSwapByOutput(uint256, SwapOrder memory, address)
        internal
        view
        virtual
        returns (uint256 feeAmount)
    {
        return 0;
    }

    /// @dev Override and implement in the hook test contracts as needed.
    function _calculateHookFeeAfterSwapSwapByOutput(uint256, SwapOrder memory, address)
        internal
        view
        virtual
        returns (uint256 feeAmount)
    {
        return 0;
    }

    function _initializeProtocolFees(SwapTestCache memory cache, SwapOrder memory swapOrder) internal view {
        cache.tokenIn = swapOrder.tokenIn;
        cache.tokenOut = swapOrder.tokenOut;
        if (cache.tokenIn < cache.tokenOut) {
            cache.protocolFees0 = amm.getProtocolFees(cache.tokenIn);
            cache.protocolFees1 = amm.getProtocolFees(cache.tokenOut);
        } else {
            cache.protocolFees0 = amm.getProtocolFees(cache.tokenOut);
            cache.protocolFees1 = amm.getProtocolFees(cache.tokenIn);
        }
    }

    function _getProtocolFeeStructure(
        bytes32 poolId,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory feeOnTop
    ) internal view returns (ProtocolFeeStructure memory protocolFeeStructure) {
        protocolFeeStructure = amm.getProtocolFeeStructure(exchangeFee.recipient, feeOnTop.recipient, poolId);
    }

    function test_singleSwap_revert_InvalidPoolID() public {
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(alice),
                amountSpecified: 1,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            bytes32("fake pool"),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            "",
            bytes4(LBAMM__InvalidPoolId.selector)
        );

        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(alice),
                amountSpecified: -1,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            bytes32("fake pool"),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            "",
            bytes4(LBAMM__InvalidPoolId.selector)
        );
    }

    function test_singleSwap_revert_InvalidRecipient() public {
        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(0),
                amountSpecified: 1,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            bytes32("fake pool"),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            "",
            bytes4(LBAMM__RecipientCannotBeAddressZero.selector)
        );

        _executeSingleSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(0),
                amountSpecified: -1,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            bytes32("fake pool"),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            "",
            bytes4(LBAMM__RecipientCannotBeAddressZero.selector)
        );
    }

    function test_multiSwap_revert_InvalidDeadline() public {
        _executeMultiSwap(
            SwapOrder({
                deadline: block.timestamp - 1,
                recipient: address(alice),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            new bytes32[](0),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            new SwapHooksExtraData[](0),
            "",
            bytes4(LBAMM__DeadlineExpired.selector)
        );
    }

    function test_multiSwap_revert_InvalidRecipient() public {
        _executeMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(0),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            new bytes32[](0),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            new SwapHooksExtraData[](0),
            "",
            bytes4(LBAMM__RecipientCannotBeAddressZero.selector)
        );
    }

    function test_multiSwap_revert_InvalidFeeOnTopRecipient() public {
        _executeMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(alice),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            new bytes32[](0),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 1, recipient: address(0)}),
            new SwapHooksExtraData[](0),
            "",
            bytes4(LBAMM__FeeRecipientCannotBeAddressZero.selector)
        );
    }

    function test_multiSwap_revert_InvalidExchangeFeeRecipient() public {
        _executeMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(alice),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            new bytes32[](0),
            BPSFeeWithRecipient({BPS: 1, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            new SwapHooksExtraData[](0),
            "",
            bytes4(LBAMM__FeeRecipientCannotBeAddressZero.selector)
        );
    }

    function test_multiSwap_revert_NoPoolsProvidedForMultiswap() public {
        _executeMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(alice),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            new bytes32[](0),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            new SwapHooksExtraData[](0),
            "",
            bytes4(LBAMM__NoPoolsProvidedForMultiswap.selector)
        );
    }

    function test_multiSwap_revert_LBAMM__InvalidExtraDataArrayLength() public {
        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = bytes32("###");
        _executeMultiSwap(
            SwapOrder({
                deadline: block.timestamp + 1,
                recipient: address(alice),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                tokenIn: address(usdc),
                tokenOut: address(weth)
            }),
            poolIds,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            new SwapHooksExtraData[](0),
            "",
            bytes4(LBAMM__InvalidExtraDataArrayLength.selector)
        );
    }
}
