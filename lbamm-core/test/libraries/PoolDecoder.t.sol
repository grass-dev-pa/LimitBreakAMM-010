pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import "src/Constants.sol";

import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";
import "src/DataTypes.sol";
import "src/Errors.sol";
import {PoolDecoder} from "src/libraries/PoolDecoder.sol";

contract PoolDecoderTest is Test {
    Handler_PoolDecoder public poolDecoder;

    bytes32 constant POOL_HASH_MASK = 0x0000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000;

    function setUp() public {
        poolDecoder = new Handler_PoolDecoder();
    }

    function testFuzz_getPoolFee(address poolType, uint16 fee, address token0, address token1, address poolHook)
        public
        view
    {
        PoolCreationDetails memory details =
            _sanitizePoolCreationDetails(poolType, fee, token0, token1, poolHook, bytes(""));

        bytes32 poolId = _generatePoolId(details);
        uint16 result = poolDecoder.getPoolFee(poolId);
        assertEq(result, details.fee);
    }

    function test_fuzz_getPoolType(address poolType, uint16 fee, address token0, address token1, address poolHook)
        public
        view
    {
        PoolCreationDetails memory details =
            _sanitizePoolCreationDetails(poolType, fee, token0, token1, poolHook, bytes(""));

        bytes32 poolId = _generatePoolId(details);
        address result = poolDecoder.getPoolType(poolId);
        assertEq(result, details.poolType);
    }

    function _sanitizePoolCreationDetails(
        address poolType,
        uint16 fee,
        address token0,
        address token1,
        address poolHook,
        bytes memory poolParams
    ) internal pure returns (PoolCreationDetails memory details) {
        uint256 ADDRESS_MASK = 0x0000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFF;

        details.poolType = address(uint160(uint256(uint160(poolType)) & ADDRESS_MASK));
        details.fee = uint16(bound(fee, 0, MAX_BPS));
        details.token0 = token0;
        details.token1 = token1;
        details.poolHook = poolHook;
        details.poolParams = poolParams;
    }

    function _generatePoolId(PoolCreationDetails memory poolCreationDetails) internal pure returns (bytes32 poolId) {
        poolId = EfficientHash.efficientHash(
            bytes32(uint256(uint160(address(poolCreationDetails.poolType)))),
            bytes32(uint256(poolCreationDetails.fee)),
            bytes32("empty placeholder"),
            bytes32(uint256(uint160(poolCreationDetails.token0))),
            bytes32(uint256(uint160(poolCreationDetails.token1))),
            bytes32(uint256(uint160(poolCreationDetails.poolHook)))
        ) & POOL_HASH_MASK;

        poolId = poolId
            | bytes32((uint256(uint160(address(poolCreationDetails.poolType))) << POOL_ID_TYPE_ADDRESS_SHIFT))
            | bytes32(uint256(poolCreationDetails.fee) << POOL_ID_FEE_SHIFT);
    }
}

contract Handler_PoolDecoder {
    function getPoolFee(bytes32 poolId) external pure returns (uint16) {
        return PoolDecoder.getPoolFee(poolId);
    }

    function getPoolType(bytes32 poolId) external pure returns (address) {
        return PoolDecoder.getPoolType(poolId);
    }
}
