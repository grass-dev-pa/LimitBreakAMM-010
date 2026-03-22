pragma solidity ^0.8.24;

import "./LBAMMCoreBase.t.sol";
import {StdStorage, stdStorage} from "forge-std/Test.sol";

import {AMMModule} from "src/modules/AMMModule.sol";

contract LBAMMModuleTest is LBAMMCoreBaseTest {
    AMMModuleHandler public handler;

    function setUp() public override {
        super.setUp();
        handler = new AMMModuleHandler(address(wrappedNative));
    }

    function test_storeProtocolFees_revert_Overflow() public {
        handler.storeProtocolFees(address(usdc), type(uint256).max);
        vm.expectRevert(LBAMM__Overflow.selector);
        handler.storeProtocolFees(address(usdc), 1);
    }

    function test_storeHookFees_revert_Overflow() public {
        TokenSettings memory usdcSettings =
            TokenSettings({hopFeeBPS: 0, packedSettings: uint32(0), tokenHook: address(0)});
        handler.storeHookFees(address(usdc), address(usdc), usdcSettings, type(uint256).max);
        vm.expectRevert(LBAMM__Overflow.selector);
        handler.storeHookFees(address(usdc), address(usdc), usdcSettings, 1);
    }

    function test_transferTokensOwed_revert_TransferFailed() public {
        handler.storeTokensOwed(address(this), address(usdc), 10);
        vm.expectRevert(LBAMM__TokenOwedTransferFailed.selector);
        handler.transferTokensOwed(address(this), address(usdc));
    }

    function test_storeTokensOwed_revert_Overflow() public {
        handler.storeTokensOwed(address(this), address(usdc), type(uint256).max);
        vm.expectRevert(LBAMM__Overflow.selector);
        handler.storeTokensOwed(address(this), address(usdc), 1);
    }

    function test_transferHookFeesByToken_revert_Underflow() public {
        TokenSettings memory usdcSettings =
            TokenSettings({hopFeeBPS: 0, packedSettings: uint32(0), tokenHook: address(0)});
        handler.storeHookFees(address(usdc), address(usdc), usdcSettings, 10);
        vm.expectRevert(LBAMM__Underflow.selector);
        handler.transferHookFeesByToken(address(usdc), address(usdc), address(this), 11);
    }

    function test_transferHookFeesByToken_revert_TransferFailed() public {
        TokenSettings memory usdcSettings =
            TokenSettings({hopFeeBPS: 0, packedSettings: uint32(0), tokenHook: address(0)});
        handler.storeHookFees(address(usdc), address(usdc), usdcSettings, 10);
        vm.expectRevert(LBAMM__TransferHookFeeTransferFailed.selector);
        handler.transferHookFeesByToken(address(usdc), address(usdc), address(this), 10);
    }

    function test_transferHookFeesByHook_revert_Underflow() public {
        TokenSettings memory usdcSettings = TokenSettings({
            hopFeeBPS: 0,
            packedSettings: uint32(TOKEN_SETTINGS_HOOK_MANAGES_FEES_FLAG),
            tokenHook: address(333)
        });
        handler.storeHookFees(address(usdc), address(usdc), usdcSettings, 10);
        vm.expectRevert(LBAMM__Underflow.selector);
        handler.transferHookFeesByHook(address(333), address(usdc), address(usdc), address(this), 11);
    }

    function test_transferHookFeesByHookRevert_TransferFailed() public {
        TokenSettings memory usdcSettings = TokenSettings({
            hopFeeBPS: 0,
            packedSettings: uint32(TOKEN_SETTINGS_HOOK_MANAGES_FEES_FLAG),
            tokenHook: address(333)
        });
        handler.storeHookFees(address(usdc), address(usdc), usdcSettings, 10);
        vm.expectRevert(LBAMM__TransferHookFeeTransferFailed.selector);
        handler.transferHookFeesByHook(address(333), address(usdc), address(usdc), address(this), 10);
    }

    function test_requirePoolIsCreated_revert_PoolDoesNotExist() public {
        vm.expectRevert(LBAMM__PoolDoesNotExist.selector);
        handler.requirePoolIsCreated(bytes32("nonexistent_pool"));
    }

    function test_validateProtocolFees_revert_FeesExceedInput() public {
        vm.expectRevert(LBAMM__FeeAmountExceedsInputAmount.selector);
        handler.validateProtocolFees(1_000, 0, 1_000, 1, true);
    }

    function test_validateProtocolFees_revert_InsufficientProtocolFee() public {
        vm.expectRevert(LBAMM__InsufficientProtocolFee.selector);
        handler.validateProtocolFees(10_000, 1_000, 1_000, 99, true, 2_500);
    }
}

contract AMMModuleHandler is AMMModule {
    constructor(address _wrappedNative)
        AMMModule(_wrappedNative)
    {}

    function storeProtocolFees(address token, uint256 amount) external {
        _storeProtocolFees(token, amount);
    }

    function storeHookFees(address tokenFor, address tokenFee, TokenSettings memory tokenForSettings, uint256 feeAmount)
        external
    {
        _storeHookFees(tokenFor, tokenFee, tokenForSettings, feeAmount);
    }

    function storeTokensOwed(address owedTo, address tokenOwed, uint256 amount) external {
        _storeTokensOwed(owedTo, tokenOwed, amount);
    }

    function transferTokensOwed(address owedTo, address tokenOwed) external {
        _transferTokensOwed(owedTo, tokenOwed);
    }

    function transferHookFeesByToken(address tokenFor, address tokenFee, address recipient, uint256 amount) external {
        _transferHookFeesByToken(tokenFor, tokenFee, recipient, amount);
    }

    function transferHookFeesByHook(address hook, address tokenFor, address tokenFee, address recipient, uint256 amount)
        external
    {
        _transferHookFeesByHook(hook, tokenFor, tokenFee, recipient, amount);
    }

    function requirePoolIsCreated(bytes32 pool) external view {
        _requirePoolIsCreated(pool);
    }

    function validateProtocolFees(
        uint256 amountIn,
        uint16 lpFeeBPS,
        uint256 poolFeeOfAmountIn,
        uint256 poolProtocolFees,
        bool inputSwap
    ) external pure returns (uint256) {
        InternalSwapCache memory swapCache;
        swapCache.amountIn = amountIn;
        swapCache.expectedLPFee = poolFeeOfAmountIn + poolProtocolFees;
        swapCache.expectedProtocolLPFee = FullMath.mulDiv(poolFeeOfAmountIn + poolProtocolFees, lpFeeBPS, MAX_BPS);

        return _validateProtocolFees(swapCache, poolFeeOfAmountIn, poolProtocolFees, inputSwap);
    }

    function validateProtocolFees(
        uint256 amountIn,
        uint16 lpFeeBPS,
        uint256 poolFeeOfAmountIn,
        uint256 poolProtocolFees,
        bool inputSwap,
        uint256 expectedLPFee
    ) external pure returns (uint256) {
        InternalSwapCache memory swapCache;
        swapCache.amountIn = amountIn;
        swapCache.expectedLPFee = expectedLPFee;
        swapCache.expectedProtocolLPFee = FullMath.mulDiv(expectedLPFee, lpFeeBPS, MAX_BPS);

        return _validateProtocolFees(swapCache, poolFeeOfAmountIn, poolProtocolFees, inputSwap);
    }
}