pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "src/libraries/BitMath.sol";

contract BitMathTest is Test {
    using BitMath for uint256;

    bytes4 constant ZERO_INPUT_ERROR_SELECTOR = bytes4(keccak256("BitMath__ZeroInput()"));

    function test_MostSignificantBit_PowersOfTwo() public pure {
        assertEq(BitMath.mostSignificantBit(1), 0);      // 2^0
        assertEq(BitMath.mostSignificantBit(2), 1);      // 2^1
        assertEq(BitMath.mostSignificantBit(4), 2);      // 2^2
        assertEq(BitMath.mostSignificantBit(8), 3);      // 2^3
        assertEq(BitMath.mostSignificantBit(16), 4);     // 2^4
        assertEq(BitMath.mostSignificantBit(32), 5);     // 2^5
        assertEq(BitMath.mostSignificantBit(64), 6);     // 2^6
        assertEq(BitMath.mostSignificantBit(128), 7);    // 2^7
        assertEq(BitMath.mostSignificantBit(256), 8);    // 2^8
        assertEq(BitMath.mostSignificantBit(512), 9);    // 2^9
        assertEq(BitMath.mostSignificantBit(1024), 10);  // 2^10
    }

    function test_MostSignificantBit_LargePowersOfTwo() public pure {
        assertEq(BitMath.mostSignificantBit(2**32), 32);
        assertEq(BitMath.mostSignificantBit(2**64), 64);
        assertEq(BitMath.mostSignificantBit(2**128), 128);
        assertEq(BitMath.mostSignificantBit(2**200), 200);
        assertEq(BitMath.mostSignificantBit(2**255), 255);
    }

    function test_MostSignificantBit_PowersOfTwoMinusOne() public pure {
        assertEq(BitMath.mostSignificantBit(3), 1);      // 2^2 - 1
        assertEq(BitMath.mostSignificantBit(7), 2);      // 2^3 - 1
        assertEq(BitMath.mostSignificantBit(15), 3);     // 2^4 - 1
        assertEq(BitMath.mostSignificantBit(31), 4);     // 2^5 - 1
        assertEq(BitMath.mostSignificantBit(63), 5);     // 2^6 - 1
        assertEq(BitMath.mostSignificantBit(127), 6);    // 2^7 - 1
        assertEq(BitMath.mostSignificantBit(255), 7);    // 2^8 - 1
    }

    function test_MostSignificantBit_RandomValues() public pure {
        assertEq(BitMath.mostSignificantBit(100), 6);    // 1100100 binary
        assertEq(BitMath.mostSignificantBit(300), 8);    // 100101100 binary
        assertEq(BitMath.mostSignificantBit(1000), 9);   // 1111101000 binary
        assertEq(BitMath.mostSignificantBit(1234567), 20); // Large number
        assertEq(BitMath.mostSignificantBit(type(uint256).max), 255); // Max uint256
    }

    function test_MostSignificantBit_EdgeCases() public pure {
        assertEq(BitMath.mostSignificantBit(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF), 127); // 2^128 - 1
        assertEq(BitMath.mostSignificantBit(0x100000000000000000000000000000000), 128); // 2^128
        assertEq(BitMath.mostSignificantBit(0xFFFFFFFF), 31); // 2^32 - 1
        assertEq(BitMath.mostSignificantBit(0x100000000), 32); // 2^32
    }

    function test_MostSignificantBit_RevertOnZero() public {
        vm.expectRevert(ZERO_INPUT_ERROR_SELECTOR);
        BitMath.mostSignificantBit(0);
    }

    function test_LeastSignificantBit_PowersOfTwo() public pure {
        assertEq(BitMath.leastSignificantBit(1), 0);      // 2^0
        assertEq(BitMath.leastSignificantBit(2), 1);      // 2^1
        assertEq(BitMath.leastSignificantBit(4), 2);      // 2^2
        assertEq(BitMath.leastSignificantBit(8), 3);      // 2^3
        assertEq(BitMath.leastSignificantBit(16), 4);     // 2^4
        assertEq(BitMath.leastSignificantBit(32), 5);     // 2^5
        assertEq(BitMath.leastSignificantBit(64), 6);     // 2^6
        assertEq(BitMath.leastSignificantBit(128), 7);    // 2^7
        assertEq(BitMath.leastSignificantBit(256), 8);    // 2^8
        assertEq(BitMath.leastSignificantBit(512), 9);    // 2^9
        assertEq(BitMath.leastSignificantBit(1024), 10);  // 2^10
    }

    function test_LeastSignificantBit_LargePowersOfTwo() public pure {
        assertEq(BitMath.leastSignificantBit(2**32), 32);
        assertEq(BitMath.leastSignificantBit(2**64), 64);
        assertEq(BitMath.leastSignificantBit(2**128), 128);
        assertEq(BitMath.leastSignificantBit(2**200), 200);
        assertEq(BitMath.leastSignificantBit(2**255), 255);
    }

    function test_LeastSignificantBit_EvenNumbers() public pure {
        assertEq(BitMath.leastSignificantBit(2), 1);      // 10 binary
        assertEq(BitMath.leastSignificantBit(6), 1);      // 110 binary
        assertEq(BitMath.leastSignificantBit(10), 1);     // 1010 binary
        assertEq(BitMath.leastSignificantBit(12), 2);     // 1100 binary
        assertEq(BitMath.leastSignificantBit(20), 2);     // 10100 binary
        assertEq(BitMath.leastSignificantBit(24), 3);     // 11000 binary
    }

    function test_LeastSignificantBit_OddNumbers() public pure {
        assertEq(BitMath.leastSignificantBit(1), 0);      // 1 binary
        assertEq(BitMath.leastSignificantBit(3), 0);      // 11 binary
        assertEq(BitMath.leastSignificantBit(5), 0);      // 101 binary
        assertEq(BitMath.leastSignificantBit(7), 0);      // 111 binary
        assertEq(BitMath.leastSignificantBit(9), 0);      // 1001 binary
        assertEq(BitMath.leastSignificantBit(15), 0);     // 1111 binary
        assertEq(BitMath.leastSignificantBit(255), 0);    // All ones in lower byte
    }

    function test_LeastSignificantBit_RandomValues() public pure {
        assertEq(BitMath.leastSignificantBit(100), 2);    // 1100100 binary (LSB at 2)
        assertEq(BitMath.leastSignificantBit(96), 5);     // 1100000 binary (LSB at 5)
        assertEq(BitMath.leastSignificantBit(1000), 3);   // 1111101000 binary (LSB at 3)
        assertEq(BitMath.leastSignificantBit(1234568), 3); // Even number ending in ...1000
    }

    function test_LeastSignificantBit_MaxValues() public pure {
        assertEq(BitMath.leastSignificantBit(type(uint256).max), 0); // All bits set, LSB at 0
        assertEq(BitMath.leastSignificantBit(type(uint256).max - 1), 1); // All bits except LSB set
    }

    function test_LeastSignificantBit_RevertOnZero() public {
        vm.expectRevert(ZERO_INPUT_ERROR_SELECTOR);
        BitMath.leastSignificantBit(0);
    }

    function testFuzz_MostSignificantBit_BoundedInput(uint256 x) public pure {
        vm.assume(x > 0);
        
        uint8 msb = BitMath.mostSignificantBit(x);
        
        assertLt(msb, 256);
        
        assertGe(x, 2**msb);
        if (msb < 255) {
            assertLt(x, 2**(msb + 1));
        }
    }

    function testFuzz_LeastSignificantBit_BoundedInput(uint256 x) public pure {
        vm.assume(x > 0);
        
        uint8 lsb = BitMath.leastSignificantBit(x);
        
        assertLt(lsb, 256);
        
        assertEq(x % (2**lsb), 0);
        if (lsb < 255) {
            assertGt(x % (2**(lsb + 1)), 0);
        }
    }

    function testFuzz_PowersOfTwo_MSB_LSB_Equal(uint8 exponent) public pure {
        vm.assume(exponent < 256);
        
        uint256 powerOfTwo = 2**exponent;
        
        assertEq(BitMath.mostSignificantBit(powerOfTwo), exponent);
        assertEq(BitMath.leastSignificantBit(powerOfTwo), exponent);
        assertEq(BitMath.mostSignificantBit(powerOfTwo), BitMath.leastSignificantBit(powerOfTwo));
    }

    function testFuzz_MSB_GreaterThanOrEqualLSB(uint256 x) public pure {
        vm.assume(x > 0);
        
        uint8 msb = BitMath.mostSignificantBit(x);
        uint8 lsb = BitMath.leastSignificantBit(x);
        
        assertGe(msb, lsb);
    }

    function test_MostSignificantBit_Monotonicity() public pure {
        // Test that MSB is monotonic (doesn't decrease as x increases)
        uint256[] memory testValues = new uint256[](10);
        testValues[0] = 1;
        testValues[1] = 2;
        testValues[2] = 5;
        testValues[3] = 10;
        testValues[4] = 100;
        testValues[5] = 1000;
        testValues[6] = 10000;
        testValues[7] = 100000;
        testValues[8] = 1000000;
        testValues[9] = 10000000;
        
        uint8 prevMsb = 0;
        for (uint i = 0; i < testValues.length; i++) {
            uint8 currentMsb = BitMath.mostSignificantBit(testValues[i]);
            assertGe(currentMsb, prevMsb, "MSB should be monotonic");
            prevMsb = currentMsb;
        }
    }

    function test_BitFlipping_Properties() public pure {
        uint256 x = 682; // 1010101010 in binary (alternating bits)
        
        uint8 msb = BitMath.mostSignificantBit(x);
        uint8 lsb = BitMath.leastSignificantBit(x);
        
        // Setting additional high bits shouldn't change LSB
        uint256 xWithHighBit = x | (1 << (msb + 1));
        assertEq(BitMath.leastSignificantBit(xWithHighBit), lsb);
        
        // Setting additional low bits might change LSB
        uint256 xWithLowBit = x | 1;
        if (lsb > 0) {
            assertEq(BitMath.leastSignificantBit(xWithLowBit), 0);
        }
    }

    function test_AllSingleBitPositions() public pure {
        // Test every single bit position from 0 to 255
        for (uint8 i = 0; i < 255; i++) {
            uint256 singleBit = 1 << i;
            assertEq(BitMath.mostSignificantBit(singleBit), i);
            assertEq(BitMath.leastSignificantBit(singleBit), i);
        }
        
        // Test the highest bit (position 255) separately due to overflow concerns
        uint256 highestBit = 1 << 255;
        assertEq(BitMath.mostSignificantBit(highestBit), 255);
        assertEq(BitMath.leastSignificantBit(highestBit), 255);
    }

    function test_ConsecutiveBits() public pure {
        assertEq(BitMath.mostSignificantBit(3), 1);   // 11 binary
        assertEq(BitMath.leastSignificantBit(3), 0);  // 11 binary
        
        assertEq(BitMath.mostSignificantBit(7), 2);   // 111 binary
        assertEq(BitMath.leastSignificantBit(7), 0);  // 111 binary
        
        assertEq(BitMath.mostSignificantBit(15), 3);  // 1111 binary
        assertEq(BitMath.leastSignificantBit(15), 0); // 1111 binary
        
        assertEq(BitMath.mostSignificantBit(30), 4);  // 11110 binary
        assertEq(BitMath.leastSignificantBit(30), 1); // 11110 binary
    }
}