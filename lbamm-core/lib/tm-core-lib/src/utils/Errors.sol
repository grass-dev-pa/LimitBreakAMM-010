pragma solidity ^0.8.4;

// General Purpose Custom Errors
error Error__BadConstructorArgument();

// Authorization Errors
error RoleClient__Unauthorized();

// FullMath Errors
error FullMath__MulDivOverflowError();

// SafeCast Errors
error SafeCast__Int128Overflow();
error SafeCast__Uint128Overflow();
error SafeCast__Uint160Overflow();
error SafeCast__Uint256ToInt256Overflow();
error SafeCast__Uint256ToInt128Overflow();

// UnsafeMath Errors
error UnsafeMath__DivisionByZero();