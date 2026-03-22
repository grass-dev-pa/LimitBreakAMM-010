pragma solidity ^0.8.24;

import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";

contract MockPool {
    function getCurrentPriceX96(address, bytes32) external pure returns (uint160) {
        return 999_999_999_999_999_999_999;
    }

    function getPoolId() external view returns (bytes32) {
        bytes32 poolId = EfficientHash.efficientHash(
            bytes32(uint256(uint160(address(this)))),
            bytes32(uint256(0)),
            bytes32("empty"),
            bytes32(uint256(uint160(address(0)))),
            bytes32(uint256(uint160(address(0)))),
            bytes32(uint256(uint160(address(0))))
        ) & 0x0000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF000000000000;

        poolId = poolId | bytes32((uint256(uint160(address(this))) << 144)) | bytes32(uint256(0) << 0);
        return poolId;
    }
}