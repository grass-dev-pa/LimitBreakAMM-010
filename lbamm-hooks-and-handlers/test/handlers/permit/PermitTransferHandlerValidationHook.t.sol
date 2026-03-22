pragma solidity ^0.8.24;

import "./PermitTransferHandler.t.sol";
import "./mocks/MockTransferHandlerexecutorValidationHook.sol";

contract PermitTransferHandlerExecutorValidationHookTest is PermitTransferHandlerTest {
    address public executor0;
    address public executor1;
    uint256 private executor0Key;
    uint256 private executor1Key;

    TransferHandlerExecutorValidationHook public executorValidationHook;

    function setUp() public override {
        super.setUp();

        (executor0, executor0Key) = makeAddrAndKey("executor0");
        (executor1, executor1Key) = makeAddrAndKey("executor1");

        executorValidationHook = new TransferHandlerExecutorValidationHook();
    }

    function test_directSwapSwapByInputFillOrKill_ValidationHook() public {
        _registerTypeHashes();
        _setValidExecutor(executor0, true);

        uint256 minAmountOut = 5_000_000_000;
        int256 amountSpecified = 5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
        address tokenIn = address(usdc);
        address tokenOut = address(weth);
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
            cosignatureExpiration: deadline,
            cosignature: bytes(""),
            hook: address(executorValidationHook),
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

        _mintAndApprove(tokenOut, executor0, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        changePrank(executor0);
        console2.log("executor0: %s", executor0);
        /* (uint256 amountIn, uint256 amountOut) =  */_executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified,
                minAmountSpecified: 0,
                limitAmount: minAmountOut,
                recipient: recipient,
                deadline: deadline
            }),
            DirectSwapParams({
                swapAmount: uint256(amountSpecified),
                maxAmountOut: uint256(amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData)),
            bytes4(0)
        );
    }

    function test_directSwapSwapByInputPartialFill_ValidationHook() public {
        _registerTypeHashes();
        _setValidExecutor(executor0, true);

        uint256 minAmountOut = 5_000_000_000;
        int256 permittedAmount = 10_000_000_000;
        int256 amountSpecified = 5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
        address tokenIn = address(usdc);
        address tokenOut = address(weth);
        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient(address(0), 0);
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient(address(0), 0);
        PartialFillPermitTransfer memory permitData = PartialFillPermitTransfer({
            permitProcessor: address(transferValidator),
            from: alice,
            salt: 999,
            permitAmountSpecified: amountSpecified,
            permitLimitAmount: uint256(amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: deadline,
            cosignatureNonce: REUSABLE_COSIGNATURE_NONCE,
            cosignature: bytes(""),
            hook: address(executorValidationHook),
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

        _mintAndApprove(tokenOut, executor0, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(executor0);
        (uint256 amountIn, uint256 amountOut) = _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified,
                minAmountSpecified: 0,
                limitAmount: minAmountOut,
                recipient: recipient,
                deadline: deadline
            }),
            DirectSwapParams({
                swapAmount: uint256(amountSpecified),
                maxAmountOut: uint256(amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(0)
        );

        (amountIn, amountOut) = _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified,
                minAmountSpecified: 0,
                limitAmount: minAmountOut,
                recipient: recipient,
                deadline: deadline
            }),
            DirectSwapParams({
                swapAmount: uint256(amountSpecified),
                maxAmountOut: uint256(amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(PermitC__OrderIsEitherCancelledOrFilled.selector)
        );
    }

    function test_directSwapSwapByInputFillOrKill_ValidationHook_Revert_NotAllowed() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 amountSpecified = 5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
        address tokenIn = address(usdc);
        address tokenOut = address(weth);
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
            cosignatureExpiration: deadline,
            cosignature: bytes(""),
            hook: address(executorValidationHook),
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

        _mintAndApprove(tokenOut, executor1, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        changePrank(executor1);
        /* (uint256 amountIn, uint256 amountOut) =  */_executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified,
                minAmountSpecified: 0,
                limitAmount: minAmountOut,
                recipient: recipient,
                deadline: deadline
            }),
            DirectSwapParams({
                swapAmount: uint256(amountSpecified),
                maxAmountOut: uint256(amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData)),
            bytes4(TransferHandlerExecutorValidationHook.TransferHandlerValidator_InvalidExecutor.selector)
        );
    }

    function test_directSwapSwapByInputPartialFill_WithCosignature_Revert_NotAllowed() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 permittedAmount = 10_000_000_000;
        int256 amountSpecified = 5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
        address tokenIn = address(usdc);
        address tokenOut = address(weth);
        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient(address(0), 0);
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient(address(0), 0);
        PartialFillPermitTransfer memory permitData = PartialFillPermitTransfer({
            permitProcessor: address(transferValidator),
            from: alice,
            salt: 999,
            permitAmountSpecified: amountSpecified,
            permitLimitAmount: uint256(amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: deadline,
            cosignatureNonce: REUSABLE_COSIGNATURE_NONCE,
            cosignature: bytes(""),
            hook: address(executorValidationHook),
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

        _mintAndApprove(tokenOut, executor1, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(executor1);
        /* (uint256 amountIn, uint256 amountOut) =  */_executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified,
                minAmountSpecified: 0,
                limitAmount: minAmountOut,
                recipient: recipient,
                deadline: deadline
            }),
            DirectSwapParams({
                swapAmount: uint256(amountSpecified),
                maxAmountOut: uint256(amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(TransferHandlerExecutorValidationHook.TransferHandlerValidator_InvalidExecutor.selector)
        );
    }

    function _setValidExecutor(address executor, bool isValid) internal {
        executorValidationHook.setValidExecutor(executor, isValid);
    }
}