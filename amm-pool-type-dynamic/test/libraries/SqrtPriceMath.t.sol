pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "src/libraries/SqrtPriceMath.sol";

contract SqrtPriceMathTest is Test {
    using SqrtPriceMath for uint160;

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // sqrt(1) * 2^96
    uint160 constant SQRT_PRICE_1_4 = 39614081257132168796771975168; // sqrt(0.25) * 2^96
    uint160 constant SQRT_PRICE_4_1 = 158456325028528675187087900672; // sqrt(4) * 2^96
    
    uint128 constant LIQUIDITY_STANDARD = 1000000 * 10**18;
    uint128 constant LIQUIDITY_SMALL = 1000 * 10**18;
    uint128 constant LIQUIDITY_LARGE = 1000000000 * 10**18;

    // ============ getNextSqrtPriceFromInput Tests ============

    function test_getNextSqrtPriceFromInput_zeroForOne_standard() public pure {
        uint160 startPrice = SQRT_PRICE_1_1;
        uint256 amountIn = 1000 * 10**18;
        
        uint160 newPrice = SqrtPriceMath.getNextSqrtPriceFromInput(
            startPrice,
            LIQUIDITY_STANDARD,
            amountIn,
            true // zeroForOne
        );
        
        assertLt(newPrice, startPrice, "Price should decrease in zeroForOne swap");
        assertGt(newPrice, 0, "New price should be positive");
    }

    function test_getNextSqrtPriceFromInput_oneForZero_standard() public pure {
        uint160 startPrice = SQRT_PRICE_1_1;
        uint256 amountIn = 1000 * 10**18;
        
        uint160 newPrice = SqrtPriceMath.getNextSqrtPriceFromInput(
            startPrice,
            LIQUIDITY_STANDARD,
            amountIn,
            false // oneForZero
        );
        
        assertGt(newPrice, startPrice, "Price should increase in oneForZero swap");
    }

    function test_getNextSqrtPriceFromInput_zeroAmount() public pure {
        uint160 startPrice = SQRT_PRICE_1_1;
        
        uint160 newPrice = SqrtPriceMath.getNextSqrtPriceFromInput(
            startPrice,
            LIQUIDITY_STANDARD,
            0,
            true
        );
        
        assertEq(newPrice, startPrice, "Price should remain unchanged with zero input");
    }

    function test_getNextSqrtPriceFromInput_revert_zeroPrice() public {
        vm.expectRevert(SqrtPriceMath__InvalidPrice.selector);
        SqrtPriceMath.getNextSqrtPriceFromInput(0, LIQUIDITY_STANDARD, 1000, true);
    }

    function test_getNextSqrtPriceFromInput_revert_zeroLiquidity() public {
        vm.expectRevert(SqrtPriceMath__InvalidLiquidity.selector);
        SqrtPriceMath.getNextSqrtPriceFromInput(SQRT_PRICE_1_1, 0, 1000, true);
    }

    function test_getNextSqrtPriceFromInput_largeAmount() public pure {
        uint160 startPrice = SQRT_PRICE_1_1;
        uint256 largeAmount = 1000000 * 10**18;
        
        uint160 newPrice = SqrtPriceMath.getNextSqrtPriceFromInput(
            startPrice,
            LIQUIDITY_LARGE,
            largeAmount,
            true
        );
        
        assertLt(newPrice, startPrice, "Price should decrease with large input");
        assertGt(newPrice, MIN_SQRT_RATIO, "Price should stay above minimum");
    }

    function test__getNextSqrtPriceFromAmount1RoundingDown_revert_NotEnoughLiquidity() public {
        uint160 startPrice = SQRT_PRICE_1_1;
        uint256 amountIn = 1000 * 10**18;
        
        vm.expectRevert(SqrtPriceMath__NotEnoughLiquidity.selector);
        SqrtPriceMath._getNextSqrtPriceFromAmount1RoundingDown(startPrice, 1, amountIn, false);
    }

    // ============ getNextSqrtPriceFromOutput Tests ============

    function test_getNextSqrtPriceFromOutput_zeroForOne_standard() public pure {
        uint160 startPrice = SQRT_PRICE_1_1;
        uint256 amountOut = 500 * 10**18;
        
        uint160 newPrice = SqrtPriceMath.getNextSqrtPriceFromOutput(
            startPrice,
            LIQUIDITY_STANDARD,
            amountOut,
            true // zeroForOne
        );
        
        assertLt(newPrice, startPrice, "Price should decrease in zeroForOne output-based");
    }

    function test_getNextSqrtPriceFromOutput_oneForZero_standard() public pure {
        uint160 startPrice = SQRT_PRICE_1_1;
        uint256 amountOut = 500 * 10**18;
        
        uint160 newPrice = SqrtPriceMath.getNextSqrtPriceFromOutput(
            startPrice,
            LIQUIDITY_STANDARD,
            amountOut,
            false // oneForZero
        );
        
        assertGt(newPrice, startPrice, "Price should increase in oneForZero output-based");
    }

    function test_getNextSqrtPriceFromOutput_revert_zeroPrice() public {
        vm.expectRevert(SqrtPriceMath__InvalidPrice.selector);
        SqrtPriceMath.getNextSqrtPriceFromOutput(0, LIQUIDITY_STANDARD, 1000, true);
    }

    function test_getNextSqrtPriceFromOutput_revert_zeroLiquidity() public {
        vm.expectRevert(SqrtPriceMath__InvalidLiquidity.selector);
        SqrtPriceMath.getNextSqrtPriceFromOutput(SQRT_PRICE_1_1, 0, 1000, true);
    }

    // ============ getAmount0Delta Tests ============

    function test_getAmount0Delta_unsigned_roundUp() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_4; // Lower price
        uint160 sqrtPriceB = SQRT_PRICE_1_1; // Higher price
        
        uint256 amount0 = SqrtPriceMath.getAmount0Delta(
            sqrtPriceA,
            sqrtPriceB,
            LIQUIDITY_STANDARD,
            true // roundUp
        );
        
        assertGt(amount0, 0, "Amount0 should be positive");
        
        uint256 amount0Down = SqrtPriceMath.getAmount0Delta(
            sqrtPriceA,
            sqrtPriceB,
            LIQUIDITY_STANDARD,
            false // roundDown
        );
        
        assertGe(amount0, amount0Down, "Rounding up should give larger or equal result");
    }

    function test_getAmount0Delta_unsigned_priceOrder() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_1;
        uint160 sqrtPriceB = SQRT_PRICE_1_4;
        
        uint256 amount0_1 = SqrtPriceMath.getAmount0Delta(sqrtPriceA, sqrtPriceB, LIQUIDITY_STANDARD, true);
        uint256 amount0_2 = SqrtPriceMath.getAmount0Delta(sqrtPriceB, sqrtPriceA, LIQUIDITY_STANDARD, true);
        
        assertEq(amount0_1, amount0_2, "Amount should be same regardless of price order");
    }

    function test_getAmount0Delta_unsigned_revert_zeroPrice() public {
        vm.expectRevert(SqrtPriceMath__InvalidPrice.selector);
        SqrtPriceMath.getAmount0Delta(0, SQRT_PRICE_1_1, LIQUIDITY_STANDARD, true);
    }

    function test_getAmount0Delta_signed_positive() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_4;
        uint160 sqrtPriceB = SQRT_PRICE_1_1;
        int128 positiveLiquidity = int128(LIQUIDITY_STANDARD);
        
        int256 amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceA, sqrtPriceB, positiveLiquidity);
        
        assertGt(amount0, 0, "Amount0 should be positive for positive liquidity");
    }

    function test_getAmount0Delta_signed_negative() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_4;
        uint160 sqrtPriceB = SQRT_PRICE_1_1;
        int128 negativeLiquidity = -int128(LIQUIDITY_STANDARD);
        
        int256 amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceA, sqrtPriceB, negativeLiquidity);
        
        assertLt(amount0, 0, "Amount0 should be negative for negative liquidity");
    }

    // ============ getAmount1Delta Tests ============

    function test_getAmount1Delta_unsigned_roundUp() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_4;
        uint160 sqrtPriceB = SQRT_PRICE_1_1;
        
        uint256 amount1 = SqrtPriceMath.getAmount1Delta(
            sqrtPriceA,
            sqrtPriceB,
            LIQUIDITY_STANDARD,
            true // roundUp
        );
        
        assertGt(amount1, 0, "Amount1 should be positive");
        
        uint256 amount1Down = SqrtPriceMath.getAmount1Delta(
            sqrtPriceA,
            sqrtPriceB,
            LIQUIDITY_STANDARD,
            false // roundDown
        );
        
        assertGe(amount1, amount1Down, "Rounding up should give larger or equal result");
    }

    function test_getAmount1Delta_unsigned_symmetry() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_1;
        uint160 sqrtPriceB = SQRT_PRICE_4_1;
        
        uint256 amount1_1 = SqrtPriceMath.getAmount1Delta(sqrtPriceA, sqrtPriceB, LIQUIDITY_STANDARD, true);
        uint256 amount1_2 = SqrtPriceMath.getAmount1Delta(sqrtPriceB, sqrtPriceA, LIQUIDITY_STANDARD, true);
        
        assertEq(amount1_1, amount1_2, "Amount should be same regardless of price order");
    }

    function test_getAmount1Delta_signed_positive() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_4;
        uint160 sqrtPriceB = SQRT_PRICE_1_1;
        int128 positiveLiquidity = int128(LIQUIDITY_STANDARD);
        
        int256 amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceA, sqrtPriceB, positiveLiquidity);
        
        assertGt(amount1, 0, "Amount1 should be positive for positive liquidity");
    }

    function test_getAmount1Delta_signed_negative() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_4;
        uint160 sqrtPriceB = SQRT_PRICE_1_1;
        int128 negativeLiquidity = -int128(LIQUIDITY_STANDARD);
        
        int256 amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceA, sqrtPriceB, negativeLiquidity);
        
        assertLt(amount1, 0, "Amount1 should be negative for negative liquidity");
    }

    // ============ computeRatioX96 Tests ============

    function test_computeRatioX96_equal_amounts() public pure {
        uint256 amount0 = 1000 * 10**18;
        uint256 amount1 = 1000 * 10**18;
        
        uint160 ratio = SqrtPriceMath.computeRatioX96(amount1, amount0);
        
        assertEq(ratio, SQRT_PRICE_1_1, "Equal amounts should give 1:1 price ratio");
    }

    function test_computeRatioX96_four_to_one() public pure {
        uint256 amount0 = 1000 * 10**18;
        uint256 amount1 = 4000 * 10**18;
        
        uint160 ratio = SqrtPriceMath.computeRatioX96(amount1, amount0);
        
        assertEq(ratio, SQRT_PRICE_4_1, "4:1 ratio should give sqrt(4) price");
    }

    function test_computeRatioX96_zero_amounts() public pure {
        uint160 ratio = SqrtPriceMath.computeRatioX96(0, 0);
        
        assertEq(ratio, 2**96, "Zero amounts should default to 1:1 ratio");
    }

    function test_computeRatioX96_zero_amount1() public pure {
        uint160 ratio = SqrtPriceMath.computeRatioX96(0, 1000);
        
        assertEq(ratio, MIN_SQRT_RATIO, "Zero amount1 should give max ratio");
    }

    function test_computeRatioX96_zero_amount0() public pure {
        uint160 ratio = SqrtPriceMath.computeRatioX96(1000, 0);
        
        assertEq(ratio, MAX_SQRT_RATIO, "Zero amount0 should give min ratio");
    }

    // ============ absDiff Tests ============

    function test_absDiff_a_greater_than_b() public pure {
        uint160 a = 1000;
        uint160 b = 500;
        
        uint256 diff = SqrtPriceMath.absDiff(a, b);
        
        assertEq(diff, 500, "Should return a - b when a > b");
    }

    function test_absDiff_b_greater_than_a() public pure {
        uint160 a = 500;
        uint160 b = 1000;
        
        uint256 diff = SqrtPriceMath.absDiff(a, b);
        
        assertEq(diff, 500, "Should return b - a when b > a");
    }

    function test_absDiff_equal_values() public pure {
        uint160 a = 1000;
        uint160 b = 1000;
        
        uint256 diff = SqrtPriceMath.absDiff(a, b);
        
        assertEq(diff, 0, "Should return 0 when values are equal");
    }

    function test_absDiff_max_values() public pure {
        uint160 a = type(uint160).max;
        uint160 b = 0;
        
        uint256 diff = SqrtPriceMath.absDiff(a, b);
        
        assertEq(diff, type(uint160).max, "Should handle max values correctly");
    }

    // ============ Internal Function Edge Cases ============

    function test_getNextSqrtPriceFromAmount0RoundingUp_add_zero_amount() public pure {
        uint160 price = SqrtPriceMath.getNextSqrtPriceFromInput(
            SQRT_PRICE_1_1,
            LIQUIDITY_STANDARD,
            0,
            true
        );
        
        assertEq(price, SQRT_PRICE_1_1, "Zero amount should return original price");
    }

    // ============ Precision and Rounding Tests ============

    function test_precision_consistency_token0() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_4;
        uint160 sqrtPriceB = SQRT_PRICE_1_1;
        uint128 liquidity = LIQUIDITY_STANDARD;
        
        uint256 amount0Up = SqrtPriceMath.getAmount0Delta(sqrtPriceA, sqrtPriceB, liquidity, true);
        uint256 amount0Down = SqrtPriceMath.getAmount0Delta(sqrtPriceA, sqrtPriceB, liquidity, false);
        
        assertGe(amount0Up, amount0Down, "Rounding up should be >= rounding down");
        
        assertLe(amount0Up - amount0Down, uint256(liquidity) / 1e18 + 1, "Rounding difference should be minimal");
    }

    function test_precision_consistency_token1() public pure {
        uint160 sqrtPriceA = SQRT_PRICE_1_4;
        uint160 sqrtPriceB = SQRT_PRICE_1_1;
        uint128 liquidity = LIQUIDITY_STANDARD;
        
        uint256 amount1Up = SqrtPriceMath.getAmount1Delta(sqrtPriceA, sqrtPriceB, liquidity, true);
        uint256 amount1Down = SqrtPriceMath.getAmount1Delta(sqrtPriceA, sqrtPriceB, liquidity, false);
        
        assertGe(amount1Up, amount1Down, "Rounding up should be >= rounding down");
        
        assertLe(amount1Up - amount1Down, 1, "Token1 rounding difference should be at most 1");
    }
}