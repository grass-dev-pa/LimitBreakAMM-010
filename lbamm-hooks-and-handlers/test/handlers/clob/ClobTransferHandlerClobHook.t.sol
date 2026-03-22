pragma solidity ^0.8.24;

import "./ClobTransferHandler.t.sol";

import "./mocks/LiquidityTokenHook.sol";
import "./mocks/MockClobValidationHook.sol";

contract ClobTransferHandlerClobHookTest is ClobTransferHandlerTest {
    MockClobValidationHook internal clobHook;
    LiquidityTokenHook internal liquidityHook;
    LiquidityTokenHook internal liquidityHook0;
    LiquidityTokenHook internal liquidityHook1;

    error TransferHandlerValidator_InvalidExecutor();
    error TransferHandlerValidator_InvalidMaker();
    error LiquidityHook__LiquidityAdditionNotAllowed();
    error LiquidityHook__OrderNotAllowed();

    function setUp() public virtual override {
        super.setUp();

        clobHook = new MockClobValidationHook();
        liquidityHook = new LiquidityTokenHook();
        liquidityHook0 = new LiquidityTokenHook();
        liquidityHook1 = new LiquidityTokenHook();
    }

    function test_clobTransferHandler_hookValidateExecutor() public {
        uint256 bobDepositAmount = 1000 ether;
        _mintAndApprove(address(token0), bob, address(clob), bobDepositAmount);
        _depositToken(bob, address(token0), bobDepositAmount, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 bobOrderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(clobHook), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        clobHook.setValidMaker(bob, true);

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            bobOrderAmount,
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

        uint256 bobVirtualBalancetoken0Before = clob.makerTokenBalance(address(token0), bob);
        uint256 bobVirtualBalancetoken1Before = clob.makerTokenBalance(address(token1), bob);
        assertEq(bobVirtualBalancetoken0Before, bobDepositAmount - bobOrderAmount);
        assertEq(bobVirtualBalancetoken1Before, 0);

        SwapOrder memory order = SwapOrder({
            tokenIn: address(token0),
            tokenOut: address(token1),
            amountSpecified: amountSpecified,
            minAmountSpecified: 0,
            limitAmount: limitAmountIn,
            recipient: address(clob),
            deadline: block.timestamp + 1
        });

        _submitLimitOrderDirectSwap(
            alice,
            order,
            swapAmount,
            limitAmountOut,
            maxOutputSlippage,
            address(clobHook),
            bytes4(TransferHandlerValidator_InvalidExecutor.selector)
        );

        clobHook.setValidExecutor(alice, true);

        _submitLimitOrderDirectSwap(alice, order, swapAmount, limitAmountOut, maxOutputSlippage, address(clobHook), bytes4(0));
    }

    function test_clobTransferHandler_hookValidateMaker() public {
        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336;
        uint256 orderAmount = 1 ether;
        bytes32 groupKey = clob.generateGroupKey(address(clobHook), 1, 18);
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
            bytes4(TransferHandlerValidator_InvalidMaker.selector)
        );

        clobHook.setValidMaker(bob, true);

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

    function test_clobTransferHandler_hookValidateHandlerOrder() public {
        changePrank(token0.owner());
        _setTokenSettings(
            address(token0),
            address(liquidityHook),
            TokenFlagSettings({
                beforeSwapHook: false,
                afterSwapHook: false,
                addLiquidityHook: false,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: false,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: true
            }),
            bytes4(0)
        );

        changePrank(token1.owner());
        _setTokenSettings(
            address(token1),
            address(liquidityHook),
            TokenFlagSettings({
                beforeSwapHook: false,
                afterSwapHook: false,
                addLiquidityHook: true,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: false,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: true
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
            HooksExtraData({tokenInHook: bytes("11"), tokenOutHook: bytes(""), clobHook: bytes("")});

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(LiquidityHook__OrderNotAllowed.selector)
        );

        hooksExtraData.tokenInHook = bytes("");
        hooksExtraData.tokenOutHook = bytes("11");

        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(LiquidityHook__OrderNotAllowed.selector)
        );

        hooksExtraData.tokenInHook = bytes("");
        hooksExtraData.tokenOutHook = bytes("");

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
}
