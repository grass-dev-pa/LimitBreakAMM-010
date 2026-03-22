pragma solidity ^0.8.24;

import "./PermitTransferHandler.t.sol";

contract PermitTransferHandlerCosignerTest is PermitTransferHandlerTest {
    address public cosigner0;
    address public cosigner1;
    address public executor0;
    address public executor1;
    uint256 private cosigner0Key;
    uint256 private cosigner1Key;
    uint256 private executor0Key;
    uint256 private executor1Key;

    error Signatures__InvalidSignature();

    function setUp() public override {
        super.setUp();

        (cosigner0, cosigner0Key) = makeAddrAndKey("cosigner0");
        (cosigner1, cosigner1Key) = makeAddrAndKey("cosigner1");
        (executor0, executor0Key) = makeAddrAndKey("executor0");
        (executor1, executor1Key) = makeAddrAndKey("executor1");
    }

    function test_directSwapSwapByInputFillOrKill_WithCosignature() public {
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
            cosigner: cosigner0,
            cosignatureExpiration: deadline,
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

        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            FILL_OR_KILL_COSIGNATURE_NONCE,
            executor0,
            permitData.signature
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

    function test_directSwapSwapByInputPartialFill_WithCosignature() public {
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
            cosigner: cosigner0,
            cosignatureExpiration: deadline,
            cosignatureNonce: REUSABLE_COSIGNATURE_NONCE,
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

        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            permitData.cosignatureNonce,
            executor0,
            permitData.signature
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

    function test_directSwapSwapByInputPartialFill_WithCosignatureRevertsOnConsumedNonce() public {
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
            cosigner: cosigner0,
            cosignatureExpiration: deadline,
            cosignatureNonce: 1,
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

        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            permitData.cosignatureNonce,
            executor0,
            permitData.signature
        );

        _mintAndApprove(tokenOut, executor0, address(amm), minAmountOut * 6);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(executor0);
        assertFalse(permitTransferHandler.isCosignerNonceConsumed(permitData.cosigner, permitData.cosignatureNonce));
        (uint256 amountIn, uint256 amountOut) = _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified / 4,
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

        // Swap fails due to consumed nonce
        assertTrue(permitTransferHandler.isCosignerNonceConsumed(permitData.cosigner, permitData.cosignatureNonce));
        (amountIn, amountOut) = _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified / 4,
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
            bytes4(PermitTransferHandler__CosignatureNonceAlreadyConsumed.selector)
        );

        // Swap succeeds with new cosignature
        permitData.cosignatureNonce = 2;
        assertFalse(permitTransferHandler.isCosignerNonceConsumed(permitData.cosigner, permitData.cosignatureNonce));
        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            permitData.cosignatureNonce,
            executor0,
            permitData.signature
        );
        (amountIn, amountOut) = _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified / 4,
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

        // Swap fails due to consumed nonce
        assertTrue(permitTransferHandler.isCosignerNonceConsumed(permitData.cosigner, permitData.cosignatureNonce));
        (amountIn, amountOut) = _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified / 4,
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
            bytes4(PermitTransferHandler__CosignatureNonceAlreadyConsumed.selector)
        );

        // Swap succeeds with new cosignature
        permitData.cosignatureNonce = type(uint256).max >> 1;
        assertFalse(permitTransferHandler.isCosignerNonceConsumed(permitData.cosigner, permitData.cosignatureNonce));
        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            permitData.cosignatureNonce,
            executor0,
            permitData.signature
        );
        (amountIn, amountOut) = _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified / 4,
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

        // Swap fails due to consumed nonce
        assertTrue(permitTransferHandler.isCosignerNonceConsumed(permitData.cosigner, permitData.cosignatureNonce));
        (amountIn, amountOut) = _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified / 4,
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
            bytes4(PermitTransferHandler__CosignatureNonceAlreadyConsumed.selector)
        );
    }

    function test_directSwapSwapByInputFillOrKill_WithCosignature_Revert_NotExecutor() public {
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
            cosigner: cosigner0,
            cosignatureExpiration: deadline,
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
        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            FILL_OR_KILL_COSIGNATURE_NONCE,
            executor0,
            permitData.signature
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
            bytes4(Signatures__InvalidSignature.selector)
        );
    }

    function test_directSwapSwapByInputPartialFill_WithCosignature_Revert_NotExecutor() public {
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
            cosigner: cosigner0,
            cosignatureExpiration: deadline,
            cosignatureNonce: REUSABLE_COSIGNATURE_NONCE,
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

        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            permitData.cosignatureNonce,
            executor0,
            permitData.signature
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
            bytes4(Signatures__InvalidSignature.selector)
        );
    }

    function test_destroyCosigner() public {
        _destroyCosigner(cosigner0Key, cosigner0, bytes4(0));
    }

    function _destroyCosigner(uint256 key, address cosigner, bytes4 errorSelector) internal {
        bytes memory destroyCosignerSignature = _getCosignerDestroySignature(key, cosigner);
        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            assertFalse(permitTransferHandler.destroyedCosigners(cosigner));
            vm.expectEmit(false, false, false, true);
            emit PermitTransferHandler.DestroyedCosigner(cosigner);
        }
        permitTransferHandler.destroyCosigner(cosigner, destroyCosignerSignature);
        if (errorSelector == bytes4(0)) {
            assertTrue(permitTransferHandler.destroyedCosigners(cosigner));
        }
    }

    function test_directSwapSwapByInputPartialFill_WithCoSignature_Revert_CosignerDestroyed() public {
        _registerTypeHashes();

        _destroyCosigner(cosigner0Key, cosigner0, bytes4(0));

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
            cosigner: cosigner0,
            cosignatureExpiration: deadline,
            cosignatureNonce: REUSABLE_COSIGNATURE_NONCE,
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

        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            permitData.cosignatureNonce,
            executor0,
            permitData.signature
        );

        _mintAndApprove(tokenOut, executor0, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(executor0);
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
            bytes4(PermitTransferHandler__CosignerDestroyed.selector)
        );
    }

    function test_directSwapSwapByInputFillOrKill_WithCoSignature_Revert_CosignerDestroyed() public {
        _registerTypeHashes();

        _destroyCosigner(cosigner0Key, cosigner0, bytes4(0));

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
            cosigner: cosigner0,
            cosignatureExpiration: deadline,
            cosignatureNonce: REUSABLE_COSIGNATURE_NONCE,
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
        
        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            permitData.cosignatureNonce,
            executor0,
            permitData.signature
        );

        _mintAndApprove(tokenOut, executor0, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(executor0);
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
            bytes4(PermitTransferHandler__CosignerDestroyed.selector)
        );
    }

    function test_directSwapSwapByInputFillOrKill_revert_CosignatureExpired() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 amountSpecified = 5_000_000_000;
        uint256 deadline = block.timestamp + 1;
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
            cosigner: cosigner0,
            cosignatureExpiration: deadline,
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
        
        permitData.cosignature = _getCosignature(
            cosigner0Key,
            deadline,
            FILL_OR_KILL_COSIGNATURE_NONCE,
            executor0,
            permitData.signature
        );

        _mintAndApprove(tokenOut, executor0, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        vm.warp(block.timestamp + 2);

        changePrank(executor0);
        /* (uint256 amountIn, uint256 amountOut) =  */_executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified,
                minAmountSpecified: 0,
                limitAmount: minAmountOut,
                recipient: recipient,
                deadline: block.timestamp + 1000
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
            bytes4(PermitTransferHandler__CosignatureExpired.selector)
        );
    }

    function _getCosignerDestroySignature(uint256 signerKey_, address cosignerToDestroy)
        internal
        view
        returns (bytes memory signature)
    {
        uint256 tmpSignerKey = signerKey_;
        address tmpCosignerToDestroy = cosignerToDestroy;

        {
            bytes32 digest = ECDSA.toTypedDataHash(
                _permitTransferHandlerUniversalDomainSeperator(),
                keccak256(abi.encode(COSIGNER_SELF_DESTRUCT_TYPEHASH, bytes32(uint256(uint160(tmpCosignerToDestroy)))))
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(tmpSignerKey, digest);
            signature = abi.encodePacked(r, s, v);
        }
    }

    function _getCosignature(
        uint256 signerKey_,
        uint256 cosignatureExpiration,
        uint256 cosignatureNonce,
        address executor,
        bytes memory permitSignature
    ) internal view returns (bytes memory signature) {
        bytes32 digest = ECDSA.toTypedDataHash(
            _permitTransferHandlerDomainSeperator(),
            keccak256(abi.encode(COSIGNATURE_TYPEHASH, keccak256(permitSignature), cosignatureExpiration, cosignatureNonce, executor))
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey_, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
