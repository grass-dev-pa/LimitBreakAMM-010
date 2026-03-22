pragma solidity ^0.8.24;

import "../../HooksAndHandlersBase.t.sol";

import {CLOBTransferHandler} from "../../../src/handlers/clob/CLOBTransferHandler.sol";
import {CLOBQuotor} from "../../../src/handlers/clob/CLOBQuotor.sol";
import "../../../src/handlers/clob/DataTypes.sol";
import "../../../src/handlers/clob/Errors.sol";

contract ClobTransferHandlerTest is HooksAndHandlersBaseTest {
    CLOBTransferHandler public clob;
    CLOBQuotor public clobQuotor;

    function setUp() public virtual override {
        super.setUp();

        clob = new CLOBTransferHandler(address(amm));
        clobQuotor = new CLOBQuotor(address(clob));
    }

    function test_initializeOrderBookKey() public {
        _initializeOrderBookKey(address(token0), address(token1), address(0), 1, 18);
    }

    function test_depositToken() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));
    }

    function test_depositToken_revert_ZeroDepositOrWithdraw() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 0 ether, bytes4(CLOBTransferHandler__ZeroDepositAmount.selector));
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));
        _withdrawToken(bob, address(token0), 0 ether, bytes4(CLOBTransferHandler__ZeroWithdrawAmount.selector));
        _withdrawToken(bob, address(token0), 1000 ether, bytes4(0));
    }

    function test_depositToken_revert_TokenTransferFailed() public {
        _depositToken(bob, address(token0), 1000 ether, bytes4(CLOBTransferHandler__TransferFailed.selector));
    }

    function test_withdrawToken() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));
        _withdrawToken(bob, address(token0), 1000 ether, bytes4(0));
    }

    function test_withdrawToken_revert_InsufficientBalance() public {
        _withdrawToken(bob, address(token0), 1, bytes4(CLOBTransferHandler__InsufficientMakerBalance.selector));
    }

    function test_openOrder() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

    function test_CloseNonHeadOrderFirst() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        assertEq(1000 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce1 = _openOrder(
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

        assertEq(900 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce2 = _openOrder(
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

        assertEq(800 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderNonce2,
            groupKey,
            bytes4(0)
        );

        assertEq(900 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderNonce1,
            groupKey,
            bytes4(0)
        );

        assertEq(1000 ether, clob.makerTokenBalance(address(token0), bob));
    }

    function test_CloseHeadOrders() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        assertEq(1000 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce1 = _openOrder(
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

        assertEq(900 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce2 = _openOrder(
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

        assertEq(800 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderNonce1,
            groupKey,
            bytes4(0)
        );

        assertEq(900 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderNonce2,
            groupKey,
            bytes4(0)
        );

        assertEq(1000 ether, clob.makerTokenBalance(address(token0), bob));
    }

    function test_CloseNonHeadOrderFirstTwoBuckets() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX961 = 1e18;
        uint160 sqrtPriceX962 = 2e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        assertEq(1000 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce1 = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX961,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        assertEq(900 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce2 = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX961,
            orderAmount*2,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        assertEq(700 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce3 = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX962,
            orderAmount*3,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        assertEq(400 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce4 = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX962,
            orderAmount*4,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        assertEq(0 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX962,
            orderNonce4,
            groupKey,
            bytes4(0)
        );

        assertEq(400 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX961,
            orderNonce2,
            groupKey,
            bytes4(0)
        );

        assertEq(600 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX962,
            orderNonce3,
            groupKey,
            bytes4(0)
        );

        assertEq(900 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX961,
            orderNonce1,
            groupKey,
            bytes4(0)
        );

        assertEq(1000 ether, clob.makerTokenBalance(address(token0), bob));
    }

    function test_CloseHeadOrdersTwoBuckets() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX961 = 1e18;
        uint160 sqrtPriceX962 = 2e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        assertEq(1000 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce1 = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX961,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        assertEq(900 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce2 = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX961,
            orderAmount*2,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        assertEq(700 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce3 = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX962,
            orderAmount*3,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        assertEq(400 ether, clob.makerTokenBalance(address(token0), bob));

        uint256 orderNonce4 = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX962,
            orderAmount*4,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        assertEq(0 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX961,
            orderNonce1,
            groupKey,
            bytes4(0)
        );

        assertEq(100 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX961,
            orderNonce2,
            groupKey,
            bytes4(0)
        );

        assertEq(300 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX962,
            orderNonce3,
            groupKey,
            bytes4(0)
        );

        assertEq(600 ether, clob.makerTokenBalance(address(token0), bob));

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX962,
            orderNonce4,
            groupKey,
            bytes4(0)
        );

        assertEq(1000 ether, clob.makerTokenBalance(address(token0), bob));
    }

    function test_openOrder_revert_InsufficientMakerBalance() public {
        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount + 1,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(CLOBTransferHandler__InsufficientMakerBalance.selector)
        );
    }

    function test_openOrder_revert_OrderAmountLessThanGroupMinimum() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 1 ether - 1;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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
            bytes4(CLOBTransferHandler__OrderAmountLessThanGroupMinimum.selector)
        );
    }

    function test_openOrderMultipleOrders() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96 - 1,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96 + 10_000,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );
    }

    function test_openOrder_revert_OrderAmountExceedsMax() public {
        _mintAndApprove(address(token0), bob, address(clob), type(uint136).max);
        _depositToken(bob, address(token0), type(uint136).max, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = type(uint128).max;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount + 1,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(CLOBTransferHandler__OrderAmountExceedsMax.selector)
        );
    }

    function test_openOrder_revert_InvalidPrice() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        _openOrder(
            bob,
            address(token0),
            address(token1),
            MAX_SQRT_RATIO + 1,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(CLOBTransferHandler__InvalidSqrtPriceX96.selector)
        );

        _openOrder(
            bob,
            address(token0),
            address(token1),
            MIN_SQRT_RATIO - 1,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(CLOBTransferHandler__InvalidSqrtPriceX96.selector)
        );
    }

    function test_closeOrder() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderNonce = _openOrder(
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

        _closeOrder(bob, address(token0), address(token1), sqrtPriceX96, orderNonce, groupKey, bytes4(0));
    }

    function test_AUDITC02_closeOrderMultipleOrdersOpen() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderNonce1 = _openOrder(
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

        uint256 orderNonce2 = _openOrder(
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

        _closeOrder(bob, address(token0), address(token1), sqrtPriceX96, orderNonce1, groupKey, bytes4(0));
        bytes32 orderBookKey = clob.generateOrderBookKey(address(token0), address(token1), groupKey);
        uint256 unfilledInputAmount = clobQuotor.quoteGetInputAmountRemaining(orderBookKey, sqrtPriceX96);
        assertEq(unfilledInputAmount, orderAmount, "Unfilled input amount mismatch after first order close");
    }

    function test_AUDITC01_closeOrderNotNextOrder() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderNonce = _openOrder(
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

        orderNonce = _openOrder(
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

        _closeOrder(bob, address(token0), address(token1), sqrtPriceX96, orderNonce, groupKey, bytes4(0));
        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderNonce,
            groupKey,
            bytes4(CLOBTransferHandler__OrderInvalidFilledOrClosed.selector)
        );
    }

    function test_closeOrder_revert_InvalidMaker() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderNonce = _openOrder(
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

        _closeOrder(
            alice,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderNonce,
            groupKey,
            bytes4(CLOBTransferHandler__InvalidMaker.selector)
        );
    }

    function test_openOrder_revert_InputAmount0() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 0;
        bytes32 groupKey = clob.generateGroupKey(address(0), 0, 1);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderNonce = _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(CLOBTransferHandler__GroupMinimumCannotBeZero.selector)
        );
    }

    function test_openOrder_revert_IdenticalTokens() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 0;
        bytes32 groupKey = clob.generateGroupKey(address(0), 0, 1);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderNonce = _openOrder(
            bob,
            address(token0),
            address(token0),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(CLOBTransferHandler__CannotPairIdenticalTokens.selector)
        );
    }

    function test_closeOrder_revertOrderAlreadyFilled() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderNonce = _openOrder(
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        _closeOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderNonce,
            groupKey,
            bytes4(CLOBTransferHandler__OrderInvalidFilledOrClosed.selector)
        );
    }

    /// @dev A NOTE ABOUT FILLING ORDERS:
    ///  amountSpecified THIS IS THE MAX AMOUNT TO FILL
    ///  limitAmountIn
    ///  limitAmountOut THIS IS THE EXPECTED AMOUNT OUT
    ///  maxOutputSlippage THIS IS THE MAXIMUM ALLOWED SLIPPAGE (AKA FILL %)

    function test_fillBasicOrder_base() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + uint256(amountSpecified),
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillBasicOrder_otherPrice() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 250_541_448_375_047_946_302_209_916_928;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = calculateFixedInput(1 ether, sqrtPriceX96);
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1000 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + uint256(swapAmount),
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillBasicOrder_WrappedNativeOut() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        _openOrder(
            bob,
            address(token0),
            address(wrappedNative),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        vm.deal(alice, 1000 ether);
        changePrank(alice);
        wrappedNative.approve(address(amm), 1000 ether);

        uint256 bobVirtualBalanceWrappedNativeBefore = clob.makerTokenBalance(address(wrappedNative), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(wrappedNative),
            bytes4(0)
        );

        uint256 bobVirtualBalanceWrappedNativeAfter = clob.makerTokenBalance(address(wrappedNative), bob);
        assertEq(
            bobVirtualBalanceWrappedNativeAfter,
            bobVirtualBalanceWrappedNativeBefore + uint256(amountSpecified),
            "Maker virtual balance wrapped native mismatch after direct swap"
        );
    }

    function test_fillBasicOrder_WrappedNativeIn() public {
        vm.deal(bob, 1000 ether);
        changePrank(bob);
        wrappedNative.approve(address(clob), 1000 ether);
        wrappedNative.deposit{value: 1000 ether}();
        _depositToken(bob, address(wrappedNative), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        _openOrder(
            bob,
            address(wrappedNative),
            address(token0),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        vm.deal(alice, 1000 ether);
        changePrank(alice);
        wrappedNative.approve(address(amm), 1000 ether);

        uint256 bobVirtualBalanceToken0Before = clob.makerTokenBalance(address(token0), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(wrappedNative),
            address(token0),
            bytes4(0)
        );

        uint256 bobVirtualBalanceToken0After = clob.makerTokenBalance(address(token0), bob);
        assertEq(
            bobVirtualBalanceToken0After,
            bobVirtualBalanceToken0Before + uint256(amountSpecified),
            "Maker virtual balance token0 mismatch after direct swap"
        );
    }

    function test_fillOrder_revert_InvalidPrice() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(CLOBTransferHandler__InvalidPrice.selector)
        );
    }

    function test_fillOrder_revert_InsufficientOutputToFill() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = MIN_SQRT_RATIO + 1;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1;
        uint256 swapAmount = 0;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(CLOBTransferHandler__InsufficientOutputToFill.selector)
        );
    }

    function test_fillOrder_revert_InsufficientInputToFill() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 2 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 2.1 ether;
        uint256 swapAmount = 2.1 ether;
        uint256 limitAmountIn = 1 ether;
        uint256 limitAmountOut = 2.1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(CLOBTransferHandler__InsufficientInputToFill.selector)
        );
    }

    function test_fillOrderPartialFill() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether + 1;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + uint256(amountSpecified),
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillOrderMultipleOrders() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        _mintAndApprove(address(token0), carol, address(clob), 1000 ether);
        _depositToken(carol, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        _openOrder(
            carol,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        int256 amountSpecified = 2 ether;
        uint256 swapAmount = 2 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 2 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);
        uint256 carolVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), carol);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + orderAmount,
            "Maker virtual balance token1 mismatch after direct swap"
        );
        uint256 carolVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), carol);
        assertEq(
            carolVirtualBalancetoken1After,
            carolVirtualBalancetoken1Before + orderAmount,
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillOrderMultipleOrdersPartialFill() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        _mintAndApprove(address(token0), carol, address(clob), 1000 ether);
        _depositToken(carol, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmountBob = 1 ether;
        uint256 orderAmountCarol = 2 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmountBob,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        _openOrder(
            carol,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmountCarol,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        int256 amountSpecified = 2 ether;
        uint256 swapAmount = 2 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 2 ether;
        uint256 maxOutputSlippage = 0 ether;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);
        uint256 carolVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), carol);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + orderAmountBob,
            "Maker virtual balance token1 mismatch after direct swap"
        );
        uint256 orderRemainder = uint256(amountSpecified) - orderAmountBob;
        uint256 carolVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), carol);
        assertEq(
            carolVirtualBalancetoken1After,
            carolVirtualBalancetoken1Before + orderRemainder,
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillOrderFillWithMultipleSwaps() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 10 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 5 ether;
        uint256 swapAmount = 5 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 5 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );
        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + orderAmount,
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillMultipleOrdersOfDifferentCurrencies() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));
        _mintAndApprove(address(token1), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token1), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 10 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        _openOrder(
            bob,
            address(token1),
            address(token0),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        int256 amountSpecified = 10 ether;
        uint256 swapAmount = 10 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 10 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken0Before = clob.makerTokenBalance(address(token0), bob);
        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token1),
            address(token0),
            bytes4(0)
        );
        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken0After = clob.makerTokenBalance(address(token0), bob);
        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);

        assertEq(
            bobVirtualBalancetoken0After,
            bobVirtualBalancetoken0Before + orderAmount,
            "Maker virtual balance token0 mismatch after direct swap"
        );

        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + orderAmount,
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillMultipleOrdersDifferentPrice() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        uint256 fillAmountOrder2 = calculateFixedInput(orderAmount, sqrtPriceX96 + 100);
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96 + 100,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        int256 amountSpecified = 2 ether;
        uint256 swapAmount = orderAmount + fillAmountOrder2;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = swapAmount;
        uint256 maxOutputSlippage = 0 ether;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + swapAmount,
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillOrderOpenAnotherOrderThenFill() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

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

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + uint256(amountSpecified * 2),
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_openOrderCloseThenOpen() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 1e18;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderNonce = _openOrder(
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

        _closeOrder(bob, address(token0), address(token1), sqrtPriceX96, orderNonce, groupKey, bytes4(0));

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

    function test_fillOrderClosePartialFillOpenAnotherOrder() public {}

    function test_fillOrderPartialFill_revert_MaxOutputSlippage() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1.1 ether;
        uint256 limitAmountOut = 1.1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(CLOBTransferHandler__FillOutputExceedsMaxSlippage.selector)
        );
    }

    function test_fillOrderPartialFill_RefundExcess() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 10 ether;
        uint256 limitAmountIn = 1 ether;
        uint256 limitAmountOut = 10 ether;
        uint256 maxOutputSlippage = 10 ether;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        uint256 aliceBalanceTokenOutBefore = token1.balanceOf(alice);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 aliceBalanceTokenOutAfter = token1.balanceOf(alice);

        assertEq(
            aliceBalanceTokenOutBefore - aliceBalanceTokenOutAfter,
            uint256(amountSpecified),
            "CLOB: Alice tokenOut balance mismatch after direct swap"
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + uint256(amountSpecified),
            "Maker virtual balance token1 mismatch after direct swap"
        );
    }

    function test_fillOrderPartialFillFillOutputRemaining() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountOut = 2 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 maxOutputSlippage = 1 ether;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );
    }

    function test_ammHandleTransfer_revert_msgSenderNotAMM() public {
        vm.expectRevert(CLOBTransferHandler__CallbackMustBeFromAMM.selector);
        clob.ammHandleTransfer(
            alice,
            SwapOrder({
                tokenIn: address(0),
                tokenOut: address(0),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                recipient: address(clob),
                deadline: block.timestamp + 1
            }),
            0,
            0,
            BPSFeeWithRecipient(address(0), 0),
            FlatFeeWithRecipient(address(0), 0),
            bytes("")
        );
    }

    function test_ammHandleTransfer_revert_extraDataLengthZero() public {
        changePrank(address(amm));
        vm.expectRevert(CLOBTransferHandler__InvalidDataLength.selector);
        clob.ammHandleTransfer(
            alice,
            SwapOrder({
                tokenIn: address(0),
                tokenOut: address(0),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                recipient: address(clob),
                deadline: block.timestamp + 1
            }),
            0,
            0,
            BPSFeeWithRecipient(address(0), 0),
            FlatFeeWithRecipient(address(0), 0),
            bytes("")
        );
    }

    function test_ammHandleTransfer_revert_handlerMustBeRecipient() public {
        changePrank(address(amm));
        vm.expectRevert(CLOBTransferHandler__HandlerMustBeRecipient.selector);
        clob.ammHandleTransfer(
            alice,
            SwapOrder({
                tokenIn: address(0),
                tokenOut: address(0),
                amountSpecified: 0,
                minAmountSpecified: 0,
                limitAmount: 0,
                recipient: address(alice),
                deadline: block.timestamp + 1
            }),
            0,
            0,
            BPSFeeWithRecipient(address(0), 0),
            FlatFeeWithRecipient(address(0), 0),
            abi.encode(address(alice))
        );
    }

    function test_ammHandleTransfer_revert_OutputBasedNotAllowed() public {
        changePrank(address(amm));
        vm.expectRevert(CLOBTransferHandler__OutputBasedNotAllowed.selector);
        clob.ammHandleTransfer(
            alice,
            SwapOrder({
                tokenIn: address(0),
                tokenOut: address(0),
                amountSpecified: -1,
                minAmountSpecified: 0,
                limitAmount: 0,
                recipient: address(clob),
                deadline: block.timestamp + 1
            }),
            0,
            0,
            BPSFeeWithRecipient(address(0), 0),
            FlatFeeWithRecipient(address(0), 0),
            abi.encode(address(alice))
        );
    }

    function _initializeOrderBookKey(address tokenIn_, address tokenOut_, address hook_, uint16 base_, uint8 scale_)
        public
    {
        clob.initializeOrderBookKey(address(tokenIn_), address(tokenOut_), hook_, base_, scale_);

        bytes32 key = clob.generateOrderBookKey(
            address(tokenIn_), address(tokenOut_), clob.generateGroupKey(hook_, base_, scale_)
        );

        (address keyTokenIn, address keyTokenOut, address keyHook, uint16 keyMinBase, uint16 keyMinScale) =
            clob.orderBookKeys(key);
        assertEq(keyTokenIn, address(tokenIn_), "Token In mismatch");
        assertEq(keyTokenOut, address(tokenOut_), "Token Out mismatch");
        assertEq(keyHook, address(hook_), "Hook mismatch");
        assertEq(keyMinBase, base_, "Minimum Order Base mismatch");
        assertEq(keyMinScale, scale_, "Minimum Order Scale mismatch");
    }

    function _depositToken(address maker, address token, uint256 amount, bytes4 errorSelector) internal {
        changePrank(maker);

        uint256 balanceBeforeMaker = IERC20(token).balanceOf(maker);
        uint256 balanceBeforeClob = IERC20(token).balanceOf(address(clob));
        uint256 makerTokenBalance = clob.makerTokenBalance(token, maker);

        _handleExpectRevert(errorSelector);
        clob.depositToken(token, amount);

        if (errorSelector == bytes4(0)) {
            uint256 balanceAfterMaker = IERC20(token).balanceOf(maker);
            uint256 balanceAfterClob = IERC20(token).balanceOf(address(clob));

            assertEq(balanceAfterMaker, balanceBeforeMaker - amount, "Maker balance mismatch after deposit");
            assertEq(balanceAfterClob, balanceBeforeClob + amount, "CLOB balance mismatch after deposit");

            assertEq(
                makerTokenBalance + amount,
                clob.makerTokenBalance(token, maker),
                "CLOB virtual maker balance mismatch after deposit"
            );
        }
        vm.stopPrank();
    }

    function _withdrawToken(address maker, address token, uint256 amount, bytes4 errorSelector) internal {
        changePrank(maker);

        uint256 balanceBeforeMaker = IERC20(token).balanceOf(maker);
        uint256 balanceBeforeClob = IERC20(token).balanceOf(address(clob));
        uint256 makerTokenBalance = clob.makerTokenBalance(token, maker);

        _handleExpectRevert(errorSelector);
        clob.withdrawToken(token, amount);

        if (errorSelector == bytes4(0)) {
            uint256 balanceAfterMaker = IERC20(token).balanceOf(maker);
            uint256 balanceAfterClob = IERC20(token).balanceOf(address(clob));

            assertEq(balanceAfterMaker, balanceBeforeMaker + amount, "Maker balance mismatch after withdraw");
            assertEq(balanceAfterClob, balanceBeforeClob - amount, "CLOB balance mismatch after withdraw");

            assertEq(
                makerTokenBalance - amount,
                clob.makerTokenBalance(token, maker),
                "CLOB virtual maker balance mismatch after withdraw"
            );
        }
        vm.stopPrank();
    }

    function _openOrder(
        address maker,
        address tokenIn_,
        address tokenOut_,
        uint160 sqrtPriceX96,
        uint256 orderAmount,
        bytes32 groupKey,
        uint160 informationSqrtPriceX96,
        HooksExtraData memory hooksExtraData,
        bytes4 errorSelector
    ) internal returns (uint256 orderNonce) {
        vm.startPrank(maker);

        uint256 virtualBalanceMakerBefore = clob.makerTokenBalance(tokenIn_, maker);

        _handleExpectRevert(errorSelector);
        orderNonce = clob.openOrder(
            tokenIn_, tokenOut_, sqrtPriceX96, orderAmount, groupKey, informationSqrtPriceX96, hooksExtraData
        );

        if (errorSelector == bytes4(0)) {
            uint256 virtualBalanceMakerAfter = clob.makerTokenBalance(tokenIn_, maker);
            assertEq(
                virtualBalanceMakerBefore - orderAmount,
                virtualBalanceMakerAfter,
                "Virtual balance maker mismatch after open order"
            );
        }
    }

    function _closeOrder(
        address maker,
        address tokenIn_,
        address tokenOut_,
        uint160 sqrtPriceX96,
        uint256 orderNonce,
        bytes32 groupKey,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(maker);

        _handleExpectRevert(errorSelector);
        clob.closeOrder(tokenIn_, tokenOut_, sqrtPriceX96, orderNonce, groupKey);

        if (errorSelector == bytes4(0)) {
            // check updates to maker virtual balance based on order state
        }

        vm.stopPrank();
    }

    struct BalanceTracking {
        uint256 makerBalanceBefore;
        uint256 makerBalanceAfter;
        uint256 executorBalanceInBefore;
        uint256 executorBalanceInAfter;
        uint256 executorBalanceOutBefore;
        uint256 executorBalanceOutAfter;
        uint256 executorVirtualBalanceBefore;
        uint256 executorVirtualBalanceAfter;
    }

    function _submitLimitOrderDirectSwap(
        address executor,
        SwapOrder memory order,
        uint256 swapAmount,
        uint256 limitAmountOut,
        uint256 maxOutputSlippage,
        address clobHook,
        bytes4 errorSelector
    ) public {
        BalanceTracking memory balanceTracking;

        bytes32 groupKey = clob.generateGroupKey(clobHook, 1, 18);

        {
            balanceTracking.executorBalanceInBefore = IERC20(order.tokenIn).balanceOf(executor);
            balanceTracking.executorBalanceOutBefore = IERC20(order.tokenOut).balanceOf(executor);
            balanceTracking.executorVirtualBalanceBefore = clob.makerTokenBalance(order.tokenOut, executor);

            if (order.tokenIn == address(wrappedNative)) {
                balanceTracking.executorBalanceInBefore += executor.balance;
            } else if (order.tokenOut == address(wrappedNative)) {
                balanceTracking.executorBalanceOutBefore += executor.balance;
            }
        }

        vm.startPrank(executor);
        _executeDirectSwap(
            order,
            DirectSwapParams({
                swapAmount: swapAmount,
                maxAmountOut: limitAmountOut,
                minAmountIn: order.limitAmount
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            SwapHooksExtraData(bytes(""), bytes(""), bytes(""), bytes("")),
            bytes.concat(
                abi.encode(address(clob)),
                abi.encode(FillParams({groupKey: groupKey, maxOutputSlippage: maxOutputSlippage, hookData: bytes("")}))
            ),
            errorSelector
        );
        if (errorSelector == bytes4(0)) {
            balanceTracking.executorBalanceInAfter = IERC20(order.tokenIn).balanceOf(executor);
            balanceTracking.executorBalanceOutAfter = IERC20(order.tokenOut).balanceOf(executor);
            balanceTracking.executorVirtualBalanceAfter = clob.makerTokenBalance(order.tokenOut, executor);

            if (order.tokenIn == address(wrappedNative)) {
                balanceTracking.executorBalanceInAfter += executor.balance;
            } else if (order.tokenOut == address(wrappedNative)) {
                balanceTracking.executorBalanceOutAfter += executor.balance;
            }

            // assertEq(
            //     balanceTracking.executorBalanceOutBefore - balanceTracking.executorBalanceOutAfter
            //         - (balanceTracking.executorVirtualBalanceAfter - balanceTracking.executorVirtualBalanceBefore),
            //     amountOut,
            //     "Executor balance amountOut mismatch"
            // );

            // assertEq(
            //     balanceTracking.executorBalanceInAfter - balanceTracking.executorBalanceInBefore
            //         + (balanceTracking.executorVirtualBalanceAfter - balanceTracking.executorVirtualBalanceBefore),
            //     amountIn,
            //     "Executor balance amountIn mismatch"
            // );

            // assertEq(
            //     int256(balanceTracking.executorBalanceInAfter) - int256(balanceTracking.executorBalanceInBefore),
            //     int256(order.amountSpecified > 0 ? order.amountSpecified : -order.amountSpecified),
            //     "Executor balance tokenIn mismatch after direct swap"
            // );
        }
    }

    function _submitLimitOrderDirectSwap(
        address executor,
        int256 amountSpecified,
        uint256 minAmountSpecified,
        uint256 swapAmount,
        uint256 limitAmountIn,
        uint256 limitAmountOut,
        uint256 maxOutputSlippage,
        address tokenIn,
        address tokenOut,
        bytes4 errorSelector
    ) public {
        address clobHook = address(0);
        SwapOrder memory order = SwapOrder({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountSpecified: amountSpecified,
            minAmountSpecified: minAmountSpecified,
            limitAmount: limitAmountIn,
            recipient: address(clob),
            deadline: block.timestamp + 1
        });
        _submitLimitOrderDirectSwap(
            executor, order, swapAmount, limitAmountOut, maxOutputSlippage, clobHook, errorSelector
        );
    }

    function _submitLimitOrderDirectSwap(
        address executor,
        int256 amountSpecified,
        uint256 swapAmount,
        uint256 limitAmountIn,
        uint256 limitAmountOut,
        uint256 maxOutputSlippage,
        address tokenIn,
        address tokenOut,
        bytes4 errorSelector
    ) public {
        _submitLimitOrderDirectSwap(
            executor,
            amountSpecified,
            0,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            tokenIn,
            tokenOut,
            errorSelector
        );
    }

    function test_fillBasicOrder_revert_LimitAmountExceeded() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether - 1;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(LBAMM__LimitAmountExceeded.selector)
        );
    }

    function test_fillBasicOrder_revert_TokenInToExecuctorLessThanLimitAmount() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 2 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(LBAMM__LimitAmountNotMet.selector)
        );
    }

    function test_fillBasicOrder_revert_LBAMM__InputNotWrappedNative() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);
        vm.deal(alice, 1000 ether);
        changePrank(alice);
        wrappedNative.approve(address(amm), 1000 ether);

        bytes memory transferData = abi.encode(
            address(clob),
            FillParams({
                groupKey: clob.generateGroupKey(address(0), 1, 18),
                maxOutputSlippage: maxOutputSlippage,
                hookData: bytes("")
            })
        );

        vm.expectRevert(LBAMM__InputNotWrappedNative.selector);
        amm.directSwap{value: 1}(
            SwapOrder({
                tokenIn: address(token0),
                tokenOut: address(token1),
                amountSpecified: amountSpecified,
                minAmountSpecified: 0,
                limitAmount: limitAmountIn,
                recipient: address(clob),
                deadline: block.timestamp + 1
            }),
            DirectSwapParams({
                swapAmount: limitAmountOut,
                maxAmountOut: limitAmountOut,
                minAmountIn: limitAmountIn
            }),
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            SwapHooksExtraData(bytes(""), bytes(""), bytes(""), bytes("")),
            transferData
        );
    }

    function test_closeAfterPartialFill() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderNonce;

        {
            uint256 orderAmount = 1 ether;
            uint160 informationSqrtPriceX96 = 0;
            HooksExtraData memory hooksExtraData =
                HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

            orderNonce = _openOrder(
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
        int256 amountSpecified = 0.1 ether;
        uint256 swapAmount = 0.1 ether;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = 0.1 ether;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalanceToken1Before = clob.makerTokenBalance(address(token1), bob);

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalanceToken0Before = clob.makerTokenBalance(address(token0), bob);

        _closeOrder(bob, address(token0), address(token1), sqrtPriceX96, orderNonce, groupKey, bytes4(0));

        {
            uint256 bobVirtualBalanceToken1After = clob.makerTokenBalance(address(token1), bob);
            uint256 bobVirtualBalanceToken0After = clob.makerTokenBalance(address(token0), bob);
            uint256 diffToken0 = bobVirtualBalanceToken0After - bobVirtualBalanceToken0Before;
            uint256 diffToken1 = bobVirtualBalanceToken1After - bobVirtualBalanceToken1Before;
            console2.log(diffToken0);
            console2.log(diffToken1);
            assertEq(diffToken0 + diffToken1, 1 ether, "CLOB: partial fill order closure incorrect value returned");
        }
    }

    function test_fillBasicOrder_directSwapProtocolFees() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(token0);
        hopTokens[1] = address(token1);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0.99 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0 ether;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        uint256 AMMBalanceBeforeToken0 = IERC20(token0).balanceOf(address(amm));

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + uint256(amountSpecified),
            "Maker virtual balance token1 mismatch after direct swap"
        );

        uint256 AMMBalanceAfterToken0 = IERC20(token0).balanceOf(address(amm));

        assertEq(
            AMMBalanceAfterToken0 - AMMBalanceBeforeToken0,
            10_000_000_000_000_000,
            "Direct Swap: Protocol fee not withheld"
        );
    }

    function test_fillBasicOrder_directSwapHookFeesBeforeSwap() public {
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

        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether;
        uint256 limitAmountIn = 0.99 ether;
        uint256 limitAmountOut = 1 ether;
        uint256 maxOutputSlippage = 0 ether;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        uint256 AMMBalanceBeforeToken0 = IERC20(token0).balanceOf(address(amm));

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        console2.log("bobVirtualBalancetoken1After", bobVirtualBalancetoken1After);
        console2.log("bobVirtualBalancetoken1Before", bobVirtualBalancetoken1Before);
        console2.log("bobVirtualBalancetoken0");
        assertEq(
            bobVirtualBalancetoken1After,
            bobVirtualBalancetoken1Before + uint256(amountSpecified),
            "Maker virtual balance token1 mismatch after direct swap"
        );

        uint256 AMMBalanceAfterToken0 = IERC20(token0).balanceOf(address(amm));

        assertEq(AMMBalanceAfterToken0 - AMMBalanceBeforeToken0, 200, "Direct Swap: Hook fee not withheld");
    }

    function test_fillBasicOrder_directSwapHookFeesAfterSwap() public {
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

        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
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

        int256 amountSpecified = 1 ether;
        uint256 swapAmount = 1 ether + 200;
        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = swapAmount;
        uint256 maxOutputSlippage = 1 ether;

        _mintAndApprove(address(token0), alice, address(amm), 1000 ether);
        _mintAndApprove(address(token1), alice, address(amm), 1000 ether);

        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);

        uint256 AMMBalanceBeforeToken1 = IERC20(token1).balanceOf(address(amm));

        _submitLimitOrderDirectSwap(
            alice,
            amountSpecified,
            swapAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );

        uint256 bobVirtualBalancetoken1After = clob.makerTokenBalance(address(token1), bob);
        uint256 diff = bobVirtualBalancetoken1After - bobVirtualBalancetoken1Before;
        assertEq(diff, uint256(amountSpecified), "Maker virtual balance token1 mismatch after direct swap");

        uint256 AMMBalanceAfterToken1 = IERC20(token1).balanceOf(address(amm));

        assertEq(AMMBalanceAfterToken1 - AMMBalanceBeforeToken1, 200, "Direct Swap: Hook fee not withheld");
    }

    struct BalanceTrackingFuzz {
        uint256 virtualBalanceMakerBefore;
        uint256 virtualBalanceMakerAfter;
        uint256 balanceFillerBefore;
        uint256 balanceFillerAfter;
    }

    function test_fuzz_fillBasicOrder(bytes32 seed) public {
        address tokenIn = address(token0);
        address tokenOut = address(token1);

        _mintAndApprove(address(tokenIn), bob, address(clob), 1000 ether);
        _depositToken(bob, address(tokenIn), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = uint160(uint256(keccak256(abi.encodePacked(seed, "sqrtPriceX96"))));

        sqrtPriceX96 = uint160(bound(uint256(sqrtPriceX96), MIN_SQRT_RATIO + 1, MAX_SQRT_RATIO - 1));

        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 orderAmount = 1 ether;
        uint256 expectedFillAmount = calculateFixedInput(orderAmount, sqrtPriceX96);
        console2.log("expectedFillAmount", expectedFillAmount);
        console2.log("sqrtPriceX96", sqrtPriceX96);
        console2.log("orderAmount", orderAmount);

        BalanceTrackingFuzz memory balanceTracking;

        balanceTracking.virtualBalanceMakerBefore = clob.makerTokenBalance(address(tokenIn), bob);

        _openOrder(
            bob,
            address(tokenIn),
            address(tokenOut),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        balanceTracking.virtualBalanceMakerAfter = clob.makerTokenBalance(address(tokenIn), bob);
        assertEq(
            balanceTracking.virtualBalanceMakerBefore - orderAmount,
            balanceTracking.virtualBalanceMakerAfter,
            "Virtual balance maker mismatch after open order"
        );

        balanceTracking.virtualBalanceMakerBefore = balanceTracking.virtualBalanceMakerAfter;

        uint256 limitAmountIn = 0 ether;
        uint256 limitAmountOut = type(uint256).max;
        uint256 maxOutputSlippage = 0;

        _mintAndApprove(address(tokenOut), alice, address(amm), expectedFillAmount);

        _submitLimitOrderDirectSwap(
            alice,
            int256(orderAmount),
            expectedFillAmount,
            limitAmountIn,
            limitAmountOut,
            maxOutputSlippage,
            address(token0),
            address(token1),
            bytes4(0)
        );
    }

    function test_AUDITH01_validateCurrentPriceInOrderBooks() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 2 ether, bytes4(0));

        _mintAndApprove(address(token0), alice, address(clob), 1000 ether);
        _depositToken(alice, address(token0), 2 ether, bytes4(0));

        _mintAndApprove(address(token0), carol, address(clob), 1000 ether);
        _depositToken(carol, address(token0), 1 ether, bytes4(0));

        uint160 price_80_sqrtPriceX96 = 708_638_228_457_182_841_184_406_864_642;
        uint160 price_90_sqrtPriceX96 = 751_624_345_125_143_793_559_241_404_708;
        uint160 price_100_sqrtPriceX96 = 792_281_625_142_643_375_935_439_503_360;
        uint160 price_110_sqrtPriceX96 = 830_951_978_692_231_578_960_602_869_906;
        uint160 price_120_sqrtPriceX96 = 867_901_035_974_955_897_886_304_357_248;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);

        {
            uint256 orderAmount = 1 ether;
            bytes32 orderBookKey = clob.generateOrderBookKey(address(token0), address(token1), groupKey);
            HooksExtraData memory hooksExtraData;

            _openOrder(
                bob,
                address(token0),
                address(token1),
                price_90_sqrtPriceX96,
                orderAmount,
                groupKey,
                0,
                hooksExtraData,
                bytes4(0)
            );

            // check price is set correctly on first order
            uint160 orderBookCurrentPrice = clobQuotor.quoteGetCurrentPrice(orderBookKey);
            assertEq(orderBookCurrentPrice, price_90_sqrtPriceX96, "Order book current price mismatch");

            _openOrder(
                bob,
                address(token0),
                address(token1),
                price_100_sqrtPriceX96,
                orderAmount,
                groupKey,
                0,
                hooksExtraData,
                bytes4(0)
            );

            // check price is unchanged on second order at higher price
            orderBookCurrentPrice = clobQuotor.quoteGetCurrentPrice(orderBookKey);
            assertEq(orderBookCurrentPrice, price_90_sqrtPriceX96, "Order book current price mismatch");

            _openOrder(
                alice,
                address(token0),
                address(token1),
                price_110_sqrtPriceX96,
                orderAmount,
                groupKey,
                0,
                hooksExtraData,
                bytes4(0)
            );

            _openOrder(
                alice,
                address(token0),
                address(token1),
                price_120_sqrtPriceX96,
                orderAmount,
                groupKey,
                0,
                hooksExtraData,
                bytes4(0)
            );

            _closeOrder(alice, address(token0), address(token1), price_110_sqrtPriceX96, 2, groupKey, bytes4(0));

            _openOrder(
                carol,
                address(token0),
                address(token1),
                price_80_sqrtPriceX96,
                orderAmount,
                groupKey,
                0,
                hooksExtraData,
                bytes4(0)
            );

            // check price is updated to the new lower price
            orderBookCurrentPrice = clobQuotor.quoteGetCurrentPrice(orderBookKey);
            assertEq(orderBookCurrentPrice, price_80_sqrtPriceX96, "Order book current price mismatch");
        }

        {
            int256 amountSpecified = 1 ether;
            uint256 swapAmount = calculateFixedInput(1 ether, price_80_sqrtPriceX96);

            uint256 limitAmountIn = 0 ether;
            uint256 limitAmountOut = 1000 ether;
            uint256 maxOutputSlippage = 0;

            _mintAndApprove(address(token0), carol, address(amm), 1000 ether);
            _mintAndApprove(address(token1), carol, address(amm), 1000 ether);

            uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), carol);

            _submitLimitOrderDirectSwap(
                carol,
                amountSpecified,
                swapAmount,
                limitAmountIn,
                limitAmountOut,
                maxOutputSlippage,
                address(token0),
                address(token1),
                bytes4(0)
            );
        }

        uint160 orderBookCurrentPrice =
            clobQuotor.quoteGetCurrentPrice(clob.generateOrderBookKey(address(token0), address(token1), groupKey));

        assertEq(orderBookCurrentPrice, price_90_sqrtPriceX96, "Order book current price mismatch");
    }

    function testCannotOpenOrderWhenScaleExceedsMaximum() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 2 ether, bytes4(0));

        uint160 price_90_sqrtPriceX96 = 751_624_345_125_143_793_559_241_404_708;
        bytes32 groupKey = clob.generateGroupKey(address(0), 256, 248);

        {
            uint256 orderAmount = 1 ether;
            console2.log(clob.getGroupKeyMinimumOrder(groupKey));
            bytes32 orderBookKey = clob.generateOrderBookKey(address(token0), address(token1), groupKey);
            HooksExtraData memory hooksExtraData;

            _openOrder(
                bob,
                address(token0),
                address(token1),
                price_90_sqrtPriceX96,
                orderAmount,
                groupKey,
                0,
                hooksExtraData,
                CLOBTransferHandler__MinimumOrderScaleExceedsMaximum.selector
            );
        }
    }

    function calculateFixedInput(uint256 amountIn, uint160 sqrtPriceX96) internal pure returns (uint256 amountOut) {
        amountOut = FullMath.mulDivRoundingUp(amountIn, sqrtPriceX96, Q96);
        amountOut = FullMath.mulDivRoundingUp(amountOut, sqrtPriceX96, Q96);
    }

    function calculateFixedOutput(uint256 amountOut, uint160 sqrtPriceX96) internal pure returns (uint256 amountIn) {
        amountIn = FullMath.mulDivRoundingUp(amountOut, Q96, sqrtPriceX96);
        amountIn = FullMath.mulDivRoundingUp(amountIn, Q96, sqrtPriceX96);
    }
}
