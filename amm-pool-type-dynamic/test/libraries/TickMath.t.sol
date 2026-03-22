pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/libraries/TickMath.sol";

contract TickMathTest is Test {
    function setUp() public {}

    function test_getSqrtPriceAtTick_revert_TickTooHigh() public {
        vm.expectRevert(DynamicPool__InvalidTick.selector);
        TickMath.getSqrtPriceAtTick(MAX_TICK + 1);
    }

    function test_getTickAtSqrtPrice_revert_priceTooLow() public {
        vm.expectRevert(DynamicPool__InvalidSqrtPriceX96.selector);
        TickMath.getTickAtSqrtPrice(MIN_SQRT_RATIO - 1);
    }

    function test_getTickAtSqrtPrice_revert_priceTooHigh() public {
        vm.expectRevert(DynamicPool__InvalidSqrtPriceX96.selector);
        TickMath.getTickAtSqrtPrice(MAX_SQRT_RATIO + 1);
    }

    function test_getSqrtPriceAtTick_minTick() public pure {
        uint160 sqrtRatio = TickMath.getSqrtPriceAtTick(MIN_TICK);
        assertEq(sqrtRatio, MIN_SQRT_RATIO);
    }

    function test_getSqrtPriceAtTick_maxTick() public pure {
        uint160 sqrtRatio = TickMath.getSqrtPriceAtTick(MAX_TICK);
        assertEq(sqrtRatio, MAX_SQRT_RATIO);
    }

    function test_getTickAtSqrtPrice_minSqrtRatio() public pure {
        int24 tick = TickMath.getTickAtSqrtPrice(MIN_SQRT_RATIO);
        assertEq(tick, MIN_TICK);
    }

    function test_getTickAtSqrtPrice_maxSqrtRatio() public pure {
        int24 tick = TickMath.getTickAtSqrtPrice(MAX_SQRT_RATIO - 1);
        assertEq(tick, MAX_TICK - 1);
    }
}
