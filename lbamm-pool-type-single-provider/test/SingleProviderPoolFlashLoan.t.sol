pragma solidity ^0.8.24;

import "./SingleProviderPool.t.sol";
import "@limitbreak/lb-amm-core/src/interfaces/hooks/ILimitBreakAMMTokenHook.sol";

contract SingleProviderFlashLoanTest is SingleProviderPoolTest {
    // Mock executors for different test scenarios
    MockFlashLoanExecutor public successfulExecutor;
    MockFlashLoanExecutor public failingExecutor;
    MockFlashLoanExecutor public insufficientRepayExecutor;
    MockFlashLoanExecutor public arbitrageExecutor;

    // Events to test
    event Flashloan(
        address indexed requester,
        address indexed executor,
        address indexed loanToken,
        uint256 loanAmount,
        address feeToken,
        uint256 feeAmount
    );

    // Custom errors (add these based on your actual error definitions)
    error Executor__Failed();

    function setUp() public override {
        super.setUp();

        // Deploy mock executors
        successfulExecutor = new MockFlashLoanExecutor(address(amm), true);
        failingExecutor = new MockFlashLoanExecutor(address(amm), false);
        insufficientRepayExecutor = new MockFlashLoanExecutor(address(amm), true);
        arbitrageExecutor = new MockFlashLoanExecutor(address(amm), true);

        // Label executors for easier debugging
        vm.label(address(successfulExecutor), "Successful Executor");
        vm.label(address(failingExecutor), "Failing Executor");
        vm.label(address(insufficientRepayExecutor), "Insufficient Repay Executor");
        vm.label(address(arbitrageExecutor), "Arbitrage Executor");
    }

    // ============ Basic Flash Loan Tests ============

    function test_flashLoan_basic_success() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 1000 ether;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: abi.encode(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        uint256 expectedFee = _calculateExpectedFee(loanAmount);
        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        _executeFlashLoan(request, alice, bytes4(0));

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
        assertEq(amm.getProtocolFees(address(currency2)), expectedFee, "Protocol Fee Mismatch");
    }

    function test_AUDITC04_flashLoan_revert_magicValueNotReturned() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 1000 ether;

        successfulExecutor.setReturnValue(bytes4(0xDEADBEEF));

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: abi.encode(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        uint256 expectedFee = _calculateExpectedFee(loanAmount);
        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        _executeFlashLoan(request, alice, bytes4(LBAMM__FlashloanExecutionFailed.selector));
    }

    function test_flashLoan_zero_amount() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: 0,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _executeFlashLoan(request, alice, bytes4(0));

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), 0, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_large_amount() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 50_000 ether; // Large loan
        uint256 expectedFee = _calculateExpectedFee(loanAmount);

        // Ensure executor can repay
        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _executeFlashLoan(request, alice, bytes4(0));
    }

    function test_flashLoan_callback_failure() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: 1000 ether,
            executor: address(failingExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _executeFlashLoan(request, alice, bytes4(Executor__Failed.selector));
    }

    function test_flashLoan_revert_FlashLoansDisabled() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        changePrank(AMM_ADMIN);
        _setFlashLoanFee(10_001, bytes4(0));

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: 1000 ether,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _executeFlashLoan(request, alice, bytes4(LBAMM__FlashloansDisabled.selector));
    }

    function test_flashLoan_tokenHookFeeAndProtocolFee() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        // Set a custom token hook that charges a flat fee
        TestTokenHookFlashLoan tokenHook = new TestTokenHookFlashLoan();

        changePrank(AMM_ADMIN);
        _setFlashLoanFee(1000, bytes4(0));

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(tokenHook),
            TokenFlagSettings(false, false, false, false, false, false, false, true, true, false),
            bytes4(0)
        );

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = 11;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        uint256 balanceBeforeExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceBeforeAMM = IERC20(currency2).balanceOf(address(amm));

        changePrank(alice);
        amm.flashLoan(request);

        uint256 balanceAfterExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceAfterAMM = IERC20(currency2).balanceOf(address(amm));

        assertEq(balanceAfterExecutor, balanceBeforeExecutor - expectedFee, "Executor Balance Error");
        assertEq(balanceAfterAMM, balanceBeforeAMM + expectedFee, "AMM Balance Error");

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_tokenHookFeeOnly() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        // Set a custom token hook that charges a flat fee
        TestTokenHookFlashLoan tokenHook = new TestTokenHookFlashLoan();

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(tokenHook),
            TokenFlagSettings(false, false, false, false, false, false, false, true, false, false),
            bytes4(0)
        );

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = 10;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        uint256 balanceBeforeExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceBeforeAMM = IERC20(currency2).balanceOf(address(amm));

        changePrank(alice);
        amm.flashLoan(request);

        uint256 balanceAfterExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceAfterAMM = IERC20(currency2).balanceOf(address(amm));

        assertEq(balanceAfterExecutor, balanceBeforeExecutor - expectedFee, "Executor Balance Error");
        assertEq(balanceAfterAMM, balanceBeforeAMM + expectedFee, "AMM Balance Error");

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_revert_feeTokenHookRejectFee() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        TestTokenHookFlashLoan tokenHook = new TestTokenHookFlashLoan();

        tokenHook.setIsFeeAllowed(false);

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(tokenHook),
            TokenFlagSettings(false, false, false, false, false, false, false, true, false, false),
            bytes4(0)
        );

        _setTokenSettings(
            address(currency3),
            address(tokenHook),
            TokenFlagSettings(false, false, false, false, false, false, false, false, true, false),
            bytes4(0)
        );

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = 10;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: abi.encode(address(currency3)),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        _executeFlashLoan(request, alice, bytes4(LBAMM__FeeTokenNotAllowedForFlashloan.selector));
    }

    function test_flashLoan_onlyProtocolFee() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        changePrank(AMM_ADMIN);
        _setFlashLoanFee(100, bytes4(0));

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = _calculateExpectedFee(loanAmount);

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        changePrank(alice);
        _executeFlashLoan(request, alice, bytes4(0));

        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_feeInOtherToken() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        TestTokenHookFlashLoan tokenHook = new TestTokenHookFlashLoan();

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(tokenHook),
            TokenFlagSettings(false, false, false, false, false, false, false, true, false, false),
            bytes4(0)
        );

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = 10;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: abi.encode(address(currency3)),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);
        _mintAndApprove(address(currency3), address(successfulExecutor), address(amm), 100 ether);

        uint256 balanceBeforeExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceBeforeAMM = IERC20(currency2).balanceOf(address(amm));
        uint256 balanceBeforeAMMFeetoken = IERC20(currency3).balanceOf(address(amm));

        changePrank(alice);
        amm.flashLoan(request);

        uint256 balanceAfterExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceAfterAMM = IERC20(currency2).balanceOf(address(amm));
        uint256 balanceAfterAMMFeetoken = IERC20(currency3).balanceOf(address(amm));

        assertEq(balanceAfterExecutor, balanceBeforeExecutor, "Executor Balance Error");
        assertEq(balanceAfterAMM, balanceBeforeAMM, "AMM Balance Error");
        assertEq(balanceAfterAMMFeetoken, balanceBeforeAMMFeetoken + expectedFee, "AMM Fee Token Balance Error");

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_repayInAMM() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = _calculateExpectedFee(loanAmount);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        successfulExecutor.setRepaymentAmount(0);

        _executeFlashLoan(request, alice, bytes4(0));

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_repayInExecutor() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = _calculateExpectedFee(loanAmount);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        successfulExecutor.setRepaymentAmount(loanAmount + expectedFee);

        _executeFlashLoan(request, alice, bytes4(0));

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_repayTooMuch() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = _calculateExpectedFee(loanAmount);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        successfulExecutor.setRepaymentAmount(loanAmount * 2);

        changePrank(alice);
        amm.flashLoan(request);

        assertEq(amm.getProtocolFees(address(currency2)), loanAmount, "Protocol Fee Mismatch");

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_repayTooMuchLoanTokenFeeOtherToken() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        TestTokenHookFlashLoan tokenHook = new TestTokenHookFlashLoan();

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(tokenHook),
            TokenFlagSettings(false, false, false, false, false, false, false, true, false, false),
            bytes4(0)
        );

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = 10;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: abi.encode(address(currency3)),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);
        _mintAndApprove(address(currency3), address(successfulExecutor), address(amm), 100 ether);

        uint256 balanceBeforeExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceBeforeAMM = IERC20(currency2).balanceOf(address(amm));
        uint256 balanceBeforeAMMFeetoken = IERC20(currency3).balanceOf(address(amm));

        successfulExecutor.setRepaymentAmount(loanAmount * 2);

        changePrank(alice);
        amm.flashLoan(request);

        uint256 balanceAfterExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceAfterAMM = IERC20(currency2).balanceOf(address(amm));
        uint256 balanceAfterAMMFeetoken = IERC20(currency3).balanceOf(address(amm));

        assertEq(balanceAfterExecutor, balanceBeforeExecutor - loanAmount, "Executor Balance Error");
        assertEq(balanceAfterAMM, balanceBeforeAMM + loanAmount, "AMM Balance Error");
        assertEq(balanceAfterAMMFeetoken, balanceBeforeAMMFeetoken + expectedFee, "AMM Fee Token Balance Error");

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_PrepayTooMuchFeeTokenFeeTokenInOtherToken() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        TestTokenHookFlashLoan tokenHook = new TestTokenHookFlashLoan();

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(tokenHook),
            TokenFlagSettings(false, false, false, false, false, false, false, true, false, false),
            bytes4(0)
        );

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = 10;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: abi.encode(address(currency3)),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);
        _mintAndApprove(address(currency3), address(successfulExecutor), address(amm), 100 ether);

        uint256 balanceBeforeExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceBeforeAMM = IERC20(currency2).balanceOf(address(amm));
        uint256 balanceBeforeAMMFeetoken = IERC20(currency3).balanceOf(address(amm));

        successfulExecutor.setRepaymentAmount(0);
        successfulExecutor.setCustomFeeAmount(expectedFee * 2);

        changePrank(alice);
        amm.flashLoan(request);

        uint256 balanceAfterExecutor = IERC20(currency2).balanceOf(address(successfulExecutor));
        uint256 balanceAfterAMM = IERC20(currency2).balanceOf(address(amm));
        uint256 balanceAfterAMMFeetoken = IERC20(currency3).balanceOf(address(amm));

        assertEq(balanceAfterExecutor, balanceBeforeExecutor, "Executor Balance Error");
        assertEq(balanceAfterAMM, balanceBeforeAMM, "AMM Balance Error");
        assertEq(balanceAfterAMMFeetoken, balanceBeforeAMMFeetoken + (expectedFee * 2), "AMM Fee Token Balance Error");

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_revert_FeeTokenAddressZero() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        TestTokenHookFlashLoan tokenHook = new TestTokenHookFlashLoan();

        changePrank(currency2.owner());
        _setTokenSettings(
            address(currency2),
            address(tokenHook),
            TokenFlagSettings(false, false, false, false, false, false, false, true, false, false),
            bytes4(0)
        );

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = 10;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: abi.encode(address(0)),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);
        _mintAndApprove(address(currency3), address(successfulExecutor), address(amm), 100 ether);

        _executeFlashLoan(request, alice, bytes4(LBAMM__FlashloanFeeTokenCannotBeAddressZero.selector));
    }

    function test_flashLoan_repayPartialInExector() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = _calculateExpectedFee(loanAmount);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        successfulExecutor.setRepaymentAmount(loanAmount / 2);

        _executeFlashLoan(request, alice, bytes4(0));

        assertTrue(successfulExecutor.wasCallbackExecuted(), "Callback Not Executed");
        assertEq(successfulExecutor.lastLoanAmount(), loanAmount, "Incorrect Loan Amount Recorded");
    }

    function test_flashLoan_revert_InsufficientFundsToRepay() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 1000 ether;

        insufficientRepayExecutor.setRepaymentAmount(1);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(insufficientRepayExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        _executeFlashLoan(request, alice, bytes4(LBAMM__TokenInTransferFailed.selector));
    }

    function test_flashLoan_revert_LoanTokenDoesNotExist() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        // Use a non-existent token address
        address fakeToken = address(0x999999);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: fakeToken,
            loanAmount: 1000 ether,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        changePrank(alice);
        vm.expectRevert();
        amm.flashLoan(request);
    }

    function test_flashLoan_revert_Reentrancy() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        // Create executor that attempts reentrancy
        MockReentrantExecutor reentrantExecutor = new MockReentrantExecutor(address(amm));

        uint256 loanAmount = 1000 ether;
        uint256 expectedFee = _calculateExpectedFee(loanAmount);
        _mintAndApprove(address(currency2), address(reentrantExecutor), address(amm), loanAmount + expectedFee);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(reentrantExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        changePrank(alice);
        vm.expectRevert(); // Should fail due to reentrancy protection
        amm.flashLoan(request);
    }

    function test_flashLoan_multiplesequential() public {
        bytes32 poolId = _createStandardSingleProviderPool();
        _setupPoolLiquidity(poolId);

        uint256 loanAmount = 1000 ether;

        changePrank(address(successfulExecutor));
        currency2.approve(address(amm), type(uint256).max);

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        changePrank(alice);

        _executeFlashLoan(request, alice, bytes4(0));
        _executeFlashLoan(request, alice, bytes4(0));
        _executeFlashLoan(request, alice, bytes4(0));

        assertEq(successfulExecutor.callbackCount(), 3, "Should execute 3 callbacks");
    }

    function test_flashLoan_revert_NotEnoughLoanToken() public {
        _createStandardSingleProviderPool();

        uint256 loanAmount = 1;

        FlashloanRequest memory request = FlashloanRequest({
            loanToken: address(currency2),
            loanAmount: loanAmount,
            executor: address(successfulExecutor),
            executorData: abi.encode(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        uint256 expectedFee = _calculateExpectedFee(loanAmount);
        _mintAndApprove(address(currency2), address(successfulExecutor), address(amm), loanAmount + expectedFee);

        _executeFlashLoan(request, alice, bytes4(LBAMM__TokenOutTransferFailed.selector));
    }

    // ============ Helper Functions ============

    function _setupPoolLiquidity(bytes32 poolId) internal {
        _mintAndApprove(address(currency2), allowedLP, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), allowedLP, address(amm), 1_000_000 ether);
        _addStandardSingleProviderLiquidity(poolId);
    }

    function _executeFlashLoan(FlashloanRequest memory flashloanRequest, address caller, bytes4 expectedRevert)
        internal
    {
        uint256 ammBalanceBefore = IERC20(currency2).balanceOf(address(amm));
        uint256 protocolFeeBefore = amm.getProtocolFees(address(currency2));

        changePrank(caller);
        if (expectedRevert != bytes4(0)) {
            vm.expectRevert(expectedRevert);
        }
        amm.flashLoan(flashloanRequest);

        if (expectedRevert == bytes4(0)) {
            uint256 ammBalanceAfter = IERC20(currency2).balanceOf(address(amm));
            uint256 protocolFeeAfter = amm.getProtocolFees(address(currency2));

            assertEq(
                ammBalanceAfter,
                ammBalanceBefore + _calculateExpectedFee(flashloanRequest.loanAmount),
                "AMM Balance Error"
            );

            assertEq(
                protocolFeeAfter - protocolFeeBefore,
                _calculateExpectedFee(flashloanRequest.loanAmount),
                "Flashloan: Fee Error"
            );
        }
    }

    function _createSecondPool() internal returns (bytes32) {
        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(currency3),
            token1: address(currency2),
            fee: 3000, // Different fee
            poolType: address(singleProviderPool),
            poolHook: address(spPoolHook),
            poolParams: bytes("")
        });

        return _createSingleProviderPoolNoHookData(details, keccak256(abi.encode("second-pool")), bytes4(0));
    }

    function _setupDifferentLiquidity(bytes32 poolId) internal {
        // Add liquidity with different ratio
        SingleProviderLiquidityModificationParams memory spParams =
            SingleProviderLiquidityModificationParams({amount0: 200_000 ether, amount1: 50_000 ether});

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

    function _calculateExpectedFee(uint256 loanAmount) internal view returns (uint256) {
        uint16 flashloanFee = amm.getFlashloanFeeBPS();

        return (loanAmount * flashloanFee) / MAX_BPS;
    }
}

// ============ Mock Executor Contracts ============

contract MockFlashLoanExecutor is ILimitBreakAMMFlashloanCallback {
    address public amm;
    bool public shouldSucceed;
    bool public callbackExecuted;
    uint256 public lastLoanAmount;
    uint256 public callbackCount;
    uint256 public customRepaymentAmount;
    uint256 public customFeeAmount;
    bytes4 public returnValue = ILimitBreakAMMFlashloanCallback.flashloanCallback.selector;

    error Executor__Failed();

    constructor(address _amm, bool _shouldSucceed) {
        amm = _amm;
        shouldSucceed = _shouldSucceed;
    }

    function flashloanCallback(
        address, /* requester */
        address loanToken,
        uint256 loanAmount,
        address feeToken,
        uint256, /* feeAmount */
        bytes calldata /* callbackData */
    ) external override returns (bytes4 magicValue) {
        require(msg.sender == amm, "Only AMM can call");

        callbackExecuted = true;
        lastLoanAmount = loanAmount;
        callbackCount++;

        if (!shouldSucceed) {
            revert Executor__Failed();
        }

        // Transfer back some of the funds
        IERC20(loanToken).transfer(amm, customRepaymentAmount);
        IERC20(feeToken).transfer(amm, customFeeAmount);

        magicValue = returnValue;
    }

    function setRepaymentAmount(uint256 amount) external {
        customRepaymentAmount = amount;
    }

    function setCustomFeeAmount(uint256 amount) external {
        customFeeAmount = amount;
    }

    function setReturnValue(bytes4 value) external {
        returnValue = value;
    }

    function wasCallbackExecuted() external view returns (bool) {
        return callbackExecuted;
    }
}

contract MockReentrantExecutor is ILimitBreakAMMFlashloanCallback {
    address public amm;

    constructor(address _amm) {
        amm = _amm;
    }

    function flashloanCallback(
        address, /* requester */
        address loanToken,
        uint256 loanAmount,
        address, /* feeToken */
        uint256, /* feeAmount */
        bytes calldata /* callbackData */
    ) external override returns (bytes4 magicValue) {
        FlashloanRequest memory reentrantRequest = FlashloanRequest({
            loanToken: loanToken,
            loanAmount: loanAmount / 2,
            executor: address(this),
            executorData: bytes(""),
            tokenHookData: bytes(""),
            feeTokenHookData: bytes("")
        });

        ILimitBreakAMM(amm).flashLoan(reentrantRequest);

        magicValue = ILimitBreakAMMFlashloanCallback.flashloanCallback.selector;
    }
}

contract TestTokenHookFlashLoan is ILimitBreakAMMTokenHook {
    uint32 private constant _supportedHookFlags =
        TOKEN_SETTINGS_FLASHLOANS_FLAG | TOKEN_SETTINGS_FLASHLOANS_VALIDATE_FEE_FLAG;

    uint32 private constant _requiredHookFlags = 0;

    bool public isFeeAllowed = true;

    function setIsFeeAllowed(bool _isFeeAllowed) external {
        isFeeAllowed = _isFeeAllowed;
    }

    function beforeFlashloan(
        address, /* requester */
        address loanToken,
        uint256, /* loanAmount */
        address, /* executor */
        bytes calldata hookData
    ) external pure override returns (address feeToken, uint256 fee) {
        address token = loanToken;
        if (hookData.length == 32) {
            token = abi.decode(hookData, (address));
        }
        return (token, 10);
    }

    function validateFlashloanFee(
        address, /* requester */
        address, /* loanToken */
        uint256, /* loanAmount */
        address, /* feeToken */
        uint256, /* feeAmount */
        address, /* executor */
        bytes calldata /* hookData */
    ) external view override returns (bool allowed) {
        return isFeeAllowed;
    }

    // ============ Revert Implementations ============

    function validatePoolCreation(
        bytes32,
        address, /* creator */
        bool, /* hookForToken0 */
        PoolCreationDetails calldata, /* details */
        bytes calldata /* hookData */
    ) external pure override {
        revert("TestTokenHookFlashLoan: validatePoolCreation not implemented");
    }

    function beforeSwap(
        SwapContext calldata, /* context */
        HookSwapParams calldata, /* swapParams */
        bytes calldata /* hookData */
    ) external pure override returns (uint256 /* fee */ ) {
        revert("TestTokenHookFlashLoan: beforeSwap not implemented");
    }

    function afterSwap(
        SwapContext calldata, /* context */
        HookSwapParams calldata, /* swapParams */
        bytes calldata /* hookData */
    ) external pure override returns (uint256 /* fee */ ) {
        revert("TestTokenHookFlashLoan: afterSwap not implemented");
    }

    function validateCollectFees(
        bool, /* hookForToken0 */
        LiquidityContext calldata, /* context */
        LiquidityCollectFeesParams calldata, /* liquidityParams */
        uint256, /* fees0 */
        uint256, /* fees1 */
        bytes calldata /* hookData */
    ) external pure override returns (uint256, uint256) {
        revert("TestTokenHookFlashLoan: validateCollectFees not implemented");
    }

    function validateAddLiquidity(
        bool, /* hookForToken0 */
        LiquidityContext calldata, /* context */
        LiquidityModificationParams calldata, /* liquidityParams */
        uint256, /* deposit0 */
        uint256, /* deposit1 */
        uint256, /* fees0 */
        uint256, /* fees1 */
        bytes calldata /* hookData */
    ) external pure override returns (uint256, uint256) {
        revert("TestTokenHookFlashLoan: validateAddLiquidity not implemented");
    }

    function validateRemoveLiquidity(
        bool, /* hookForToken0 */
        LiquidityContext calldata, /* context */
        LiquidityModificationParams calldata, /* liquidityParams */
        uint256, /* withdraw0 */
        uint256, /* withdraw1 */
        uint256, /* fees0 */
        uint256, /* fees1 */
        bytes calldata /* hookData */
    ) external pure override returns (uint256, uint256) {
        revert("TestTokenHookFlashLoan: validateRemoveLiquidity not implemented");
    }

    function hookFlags() external pure returns (uint32 requiredFlags, uint32 supportedFlags) {
        return (_requiredHookFlags, _supportedHookFlags);
    }

    function tokenHookManifestUri() external pure returns (string memory manifestUri) {
        manifestUri = "";
    }
    
    function validateHandlerOrder(address, bool, address, address, uint256, uint256, bytes calldata, bytes calldata) external pure { }
}
