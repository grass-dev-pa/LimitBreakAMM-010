pragma solidity ^0.8.24;

import "../../HooksAndHandlersBase.t.sol";

import "../../../src/handlers/permit/DataTypes.sol";
import "../../../src/handlers/permit/PermitTransferHandler.sol";


import "@limitbreak/permit-c/interfaces/IPermitC.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract PermitTransferHandlerTest is HooksAndHandlersBaseTest {
    PermitTransferHandler public permitTransferHandler;
    

    /// @dev EIP-712 typehash for permit transfers with additional swap data validation
    bytes32 private PERMITTED_TRANSFER_APPROVAL_TYPEHASH;

    /// @dev EIP-712 typehash for permit orders with additional swap data validation
    bytes32 private PERMITTED_ORDER_APPROVAL_TYPEHASH;

    string constant SWAP_STUB =
        "Swap swapData)Swap(bool partialFill,address recipient,int256 amountSpecified,uint256 limitAmount,address tokenOut,address exchangeFeeRecipient,uint16 exchangeFeeBPS,address cosigner,address hook)";

    error PermitC__OrderIsEitherCancelledOrFilled();

    constructor() {
        PERMITTED_TRANSFER_APPROVAL_TYPEHASH = keccak256(
            bytes.concat(
                bytes(PERMITTED_TRANSFER_APPROVAL_TYPEHASH_STUB),
                bytes(PERMITTED_APPROVAL_TYPEHASH_EXTRADATA_STUB),
                bytes(SWAP_TYPEHASH_STUB)
            )
        );

        PERMITTED_ORDER_APPROVAL_TYPEHASH = keccak256(
            bytes.concat(
                bytes(PERMITTED_ORDER_APPROVAL_TYPEHASH_STUB),
                bytes(PERMITTED_APPROVAL_TYPEHASH_EXTRADATA_STUB),
                bytes(SWAP_TYPEHASH_STUB)
            )
        );
    }

    function setUp() public virtual override {
        super.setUp();

        token0 = new ERC20Mock("Token0", "TK0", 18);
        token1 = new ERC20Mock("Token1", "TK1", 18);

        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        permitTransferHandler = new PermitTransferHandler(address(amm));

        address[] memory whitelistAccounts = new address[](2);
        whitelistAccounts[0] = address(amm);
        whitelistAccounts[1] = address(permitTransferHandler);

        changePrank(AMM_ADMIN);
        transferValidator.addAccountsToWhitelist(0, whitelistAccounts);
        changePrank(address(this));

        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
        vm.label(address(permitTransferHandler), "Permit Transfer Handler");

        PERMITTED_TRANSFER_APPROVAL_TYPEHASH = keccak256(
            bytes.concat(
                bytes(PERMITTED_TRANSFER_APPROVAL_TYPEHASH_STUB),
                bytes(PERMITTED_APPROVAL_TYPEHASH_EXTRADATA_STUB),
                bytes(SWAP_TYPEHASH_STUB)
            )
        );

        PERMITTED_ORDER_APPROVAL_TYPEHASH = keccak256(
            bytes.concat(
                bytes(PERMITTED_ORDER_APPROVAL_TYPEHASH_STUB),
                bytes(PERMITTED_APPROVAL_TYPEHASH_EXTRADATA_STUB),
                bytes(SWAP_TYPEHASH_STUB)
            )
        );
    }

    function test_registerTypeHashes() public {
        assertFalse(transferValidator.isRegisteredTransferAdditionalDataHash(PERMITTED_TRANSFER_APPROVAL_TYPEHASH));
        _registerTypeHashes();
        assertTrue(transferValidator.isRegisteredTransferAdditionalDataHash(PERMITTED_TRANSFER_APPROVAL_TYPEHASH));
    }

    function test_directSwapSwapByInputFillOrKillWrappedNativeTokenOut() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 amountSpecified = 5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
        address tokenIn = address(usdc);
        address tokenOut = address(wrappedNative);
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

        vm.deal(bob, minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        changePrank(bob);
        wrappedNative.approve(address(amm), minAmountOut);
        amm.directSwap{value: minAmountOut}(
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
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData))
        );
    }

    function test_directSwapSwapByInputFillOrKill() public {
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        changePrank(bob);
        _executeDirectSwap(
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

    function test_directSwapSwapByOutputFillOrKill() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 amountSpecified = -5_000_000_000;
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        changePrank(bob);
        _executeDirectSwap(
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData)),
            bytes4(0)
        );
    }

    function test_directSwapSwapByInputPartialFill() public {
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
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
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

    function test_directSwapSwapByOutputPartialFill() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 permittedAmount = -10_000_000_000;
        int256 amountSpecified = -5_000_000_000;
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
            permitLimitAmount: uint256(-amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(PermitC__OrderIsEitherCancelledOrFilled.selector)
        );
    }

    function test_directSwapSwapByOutputPartialFillHookData() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 permittedAmount = -10_000_000_000;
        int256 amountSpecified = -5_000_000_000;
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
            permitLimitAmount: uint256(-amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            SwapHooksExtraData({
                tokenInHook: bytes("1"),
                tokenOutHook: bytes("111"),
                poolHook: bytes(""),
                poolType: bytes("")
            }),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(PermitC__OrderIsEitherCancelledOrFilled.selector)
        );
    }

    function test_ammHandleTransfer_revert_CallNotFromAMM() public {
        vm.expectRevert(PermitTransferHandler__CallbackMustBeFromAMM.selector);
        permitTransferHandler.ammHandleTransfer(
            address(amm),
            SwapOrder({
                tokenIn: address(token0),
                tokenOut: address(token1),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                recipient: address(0),
                deadline: block.timestamp + 1000
            }),
            0,
            0,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            bytes("")
        );
    }

    function test_ammHandleTransfer_revert_InvalidDataLength() public {
        changePrank(address(amm));
        vm.expectRevert(PermitTransferHandler__InvalidDataLength.selector);
        permitTransferHandler.ammHandleTransfer(
            address(amm),
            SwapOrder({
                tokenIn: address(token0),
                tokenOut: address(token1),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                recipient: address(0),
                deadline: block.timestamp + 1000
            }),
            0,
            0,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            bytes("")
        );
    }

    function test_ammHandleTransfer_revert_InvalidPermitType() public {
        changePrank(address(amm));
        vm.expectRevert(PermitTransferHandler__InvalidPermitType.selector);
        permitTransferHandler.ammHandleTransfer(
            address(amm),
            SwapOrder({
                tokenIn: address(token0),
                tokenOut: address(token1),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                recipient: address(0),
                deadline: block.timestamp + 1000
            }),
            0,
            0,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            abi.encode(bytes1(0x02))
        );
    }

    function test_directSwapSwapByInputPartialFill_revert_PermitTransferFailed() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
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
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);

        changePrank(bob);
        _executeDirectSwap(
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
            bytes4(PermitTransferHandler__PermitTransferFailed.selector)
        );
    }

    function test_directSwapSwapByInputFillOrKill_revert_PermitTransferFailed() public {
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut);

        changePrank(bob);
        _executeDirectSwap(
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
            bytes4(PermitTransferHandler__PermitTransferFailed.selector)
        );
    }

    function test_directSwapSwapByInputPartialFill_revert_InputOutputModeMismatch() public {
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
            permitAmountSpecified: -amountSpecified,
            permitLimitAmount: uint256(amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
        _executeDirectSwap(
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
            bytes4(PermitTransferHandler__PermitSwapInputOutputModeMismatch.selector)
        );
    }

    function test_directSwapSwapByOutputPartialFil_revert_InputOutputModeMismatch() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 permittedAmount = -10_000_000_000;
        int256 amountSpecified = -5_000_000_000;
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
            permitAmountSpecified: -amountSpecified,
            permitLimitAmount: uint256(-amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
        _executeDirectSwap(
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(PermitTransferHandler__PermitSwapInputOutputModeMismatch.selector)
        );
    }

    function test_directSwapSwapByInputPartialFill_revert_PartialFillExceedsMaximumInputForOutput() public {
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
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
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

    function test_directSwapSwapByOutputPartialFill_revert_PartialFillExceedsMaximumInputForOutput() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 permittedAmount = -10_000_000_000;
        int256 amountSpecified = -5_000_000_000;
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
            permitLimitAmount: uint256(-amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(PermitC__OrderIsEitherCancelledOrFilled.selector)
        );
    }

    function _registerTypeHashes() internal {
        transferValidator.registerAdditionalDataHash(SWAP_STUB);
    }

    function _getSignature(
        uint256 signerKey_,
        uint256 deadline,
        address tokenIn,
        address recipient,
        int256 amountSpecified_,
        uint256 limiter,
        address tokenOut,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory, /*feeOnTop*/
        FillOrKillPermitTransfer memory permitData
    ) internal view returns (bytes memory signature) {
        bytes32 additionalData;
        {
            bytes memory data = abi.encode(
                SWAP_TYPEHASH,
                false,
                recipient,
                amountSpecified_,
                limiter,
                tokenOut,
                exchangeFee.recipient,
                exchangeFee.BPS,
                permitData.cosigner,
                permitData.hook
            );
            additionalData = keccak256(data);
        }

        uint256 tmpSignerKey = signerKey_;
        uint256 tmpDeadline = deadline;
        address tmpTokenIn = tokenIn;
        permitData.from = vm.addr(tmpSignerKey);
        bytes32 digest = ECDSA.toTypedDataHash(
            IPermitC(permitData.permitProcessor).domainSeparatorV4(),
            keccak256(
                abi.encode(
                    PERMITTED_TRANSFER_APPROVAL_TYPEHASH,
                    20,
                    tmpTokenIn,
                    0,
                    permitData.permitAmount,
                    permitData.nonce,
                    address(permitTransferHandler),
                    tmpDeadline,
                    0,
                    additionalData
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(tmpSignerKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _getSignature(
        uint256 signerKey_,
        uint256 deadline,
        address tokenIn,
        address recipient,
        int256,
        uint256,
        address tokenOut,
        BPSFeeWithRecipient memory exchangeFee,
        FlatFeeWithRecipient memory, /*feeOnTop*/
        PartialFillPermitTransfer memory permitData
    ) internal view returns (bytes memory signature) {
        bytes32 additionalData;
        {
            bytes memory data = abi.encode(
                SWAP_TYPEHASH,
                true,
                recipient,
                permitData.permitAmountSpecified,
                permitData.permitLimitAmount,
                tokenOut,
                exchangeFee.recipient,
                exchangeFee.BPS,
                permitData.cosigner,
                permitData.hook
            );
            additionalData = keccak256(data);
        }

        uint256 tmpSignerKey = signerKey_;
        uint256 tmpDeadline = deadline;
        address tmpTokenIn = tokenIn;
        permitData.from = vm.addr(tmpSignerKey);
        bytes32 digest = ECDSA.toTypedDataHash(
            IPermitC(permitData.permitProcessor).domainSeparatorV4(),
            keccak256(
                abi.encode(
                    PERMITTED_ORDER_APPROVAL_TYPEHASH,
                    20,
                    tmpTokenIn,
                    0,
                    permitData.permitAmountSpecified > 0
                        ? uint256(permitData.permitAmountSpecified)
                        : permitData.permitLimitAmount,
                    permitData.salt,
                    address(permitTransferHandler),
                    tmpDeadline,
                    0,
                    additionalData
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(tmpSignerKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _permitTransferHandlerDomainSeperator() internal view returns (bytes32 domainSeperator) {
        domainSeperator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("PermitTransferHandler")),
                keccak256(bytes("1")),
                block.chainid,
                address(permitTransferHandler)
            )
        );
    }

    function _permitTransferHandlerUniversalDomainSeperator() internal view returns (bytes32 domainSeperator) {
        domainSeperator = keccak256(
            abi.encode(
                keccak256("EIP712Domain()")
            )
        );
    }

    function test_directSwapSwapByInputPartialFill_revert_ExceedMaxInput() public {
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
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
        _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified + 1,
                minAmountSpecified: 0,
                limitAmount: minAmountOut,
                recipient: recipient,
                deadline: deadline
            }),
            DirectSwapParams({
                swapAmount: uint256(amountSpecified),
                maxAmountOut: uint256(amountSpecified) + 1,
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(PermitTransferHandler__PartialFillExceedsMaximumInputForOutput.selector)
        );
    }

    function test_directSwapSwapByOutputPartialFill_revert_ExceedMaxInput() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 permittedAmount = -10_000_000_000;
        int256 amountSpecified = -5_000_000_000;
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
            permitLimitAmount: uint256(-amountSpecified),
            expiration: deadline,
            signature: bytes(""),
            cosigner: address(0),
            cosignatureExpiration: type(uint256).max,
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut * 2);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(permittedAmount));

        changePrank(bob);
        _executeDirectSwap(
            SwapOrder({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountSpecified: amountSpecified + 1,
                minAmountSpecified: 0,
                limitAmount: minAmountOut,
                recipient: recipient,
                deadline: deadline
            }),
            DirectSwapParams({
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x01), abi.encode(permitData)),
            bytes4(PermitTransferHandler__PartialFillExceedsMaximumInputForOutput.selector)
        );
    }

    function test_directSwapSwapByOutputFillOrKill_tokenHookFeesBefore() public {
        changePrank(token0.owner());
        _setTokenSettings(
            address(token0),
            address(feeHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: false,
                addLiquidityHook: false,
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

        changePrank(token1.owner());
        _setTokenSettings(
            address(token1),
            address(feeHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: false,
                addLiquidityHook: false,
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

        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_200;
        int256 amountSpecified = -5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        changePrank(bob);
        _executeDirectSwap(
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified + 200),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData)),
            bytes4(0)
        );

        console2.log("balance AMM token0", token0.balanceOf(address(amm)));
        console2.log("balance AMM token1", token1.balanceOf(address(amm)));

        assertEq(token1.balanceOf(address(amm)), 200);
    }


    function test_directSwapSwapByOutputFillOrKill_tokenHookFeesAfter() public {
        changePrank(token0.owner());
        _setTokenSettings(
            address(token0),
            address(feeHook),
            TokenFlagSettings({
                beforeSwapHook: false,
                afterSwapHook: true,
                addLiquidityHook: false,
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

        changePrank(token1.owner());
        _setTokenSettings(
            address(token1),
            address(feeHook),
            TokenFlagSettings({
                beforeSwapHook: false,
                afterSwapHook: true,
                addLiquidityHook: false,
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

        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_200;
        int256 amountSpecified = -5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        changePrank(bob);
        _executeDirectSwap(
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
                swapAmount: uint256(-amountSpecified),
                maxAmountOut: uint256(-amountSpecified + 200),
                minAmountIn: 0
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData)),
            bytes4(0)
        );

        console2.log("balance AMM token0", token0.balanceOf(address(amm)));
        console2.log("balance AMM token1", token0.balanceOf(address(amm)));

        assertEq(token0.balanceOf(address(amm)), 200);
    }

    function test_directSwapSwapByInputFillOrKill_exchangeFee() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 amountSpecified = 5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
        address tokenIn = address(usdc);
        address tokenOut = address(weth);
        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient(address(exchangeFeeRecipient), 100);
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified));

        changePrank(bob);
        _executeDirectSwap(
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
            exchangeFee,
            feeOnTop,
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData)),
            bytes4(0)
        );

        assertEq(IERC20(tokenIn).balanceOf(address(exchangeFeeRecipient)), 47500000);
        assertEq(IERC20(tokenIn).balanceOf(address(amm)), 50000000 - 47500000);
    }

    function test_directSwapSwapByInputFillOrKill_feeOnTop() public {
        _registerTypeHashes();

        uint256 minAmountOut = 5_000_000_000;
        int256 amountSpecified = 5_000_000_000;
        uint256 deadline = block.timestamp + 1000;
        address recipient = bob;
        address tokenIn = address(usdc);
        address tokenOut = address(weth);
        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient(address(0), 0);
        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient(address(feeOnTopRecipient), 1_000_000);
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

        _mintAndApprove(tokenOut, bob, address(amm), minAmountOut);
        _mintAndApprove(tokenIn, alice, address(transferValidator), uint256(amountSpecified) + feeOnTop.amount);

        changePrank(bob);
        _executeDirectSwap(
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
            exchangeFee,
            feeOnTop,
            _emptySwapHooksExtraData(),
            bytes.concat(abi.encode(address(permitTransferHandler)), bytes1(0x00), abi.encode(permitData)),
            bytes4(0)
        );

        assertEq(IERC20(tokenIn).balanceOf(address(feeOnTopRecipient)), 750_000);
        assertEq(IERC20(tokenIn).balanceOf(address(amm)), (1_000_000 - 750_000));
    }
}
