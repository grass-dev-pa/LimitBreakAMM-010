// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

abstract contract EIP712 {
    bytes32 private immutable _cachedDomainSeparator;
    bytes32 private immutable _cachedChainlessDomainSeparator;
    bytes32 private immutable _cachedUniversalDomainSeparator;

    constructor(string memory name, string memory version) {
        _cachedDomainSeparator = 
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"), 
                    keccak256(bytes(name)), 
                    keccak256(bytes(version)), 
                    block.chainid, 
                    address(this)
                )
            );

        _cachedChainlessDomainSeparator = 
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,address verifyingContract)"), 
                    keccak256(bytes(name)), 
                    keccak256(bytes(version)), 
                    address(this)
                )
            );

        _cachedUniversalDomainSeparator = 
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain()")
                )
            );
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        return _cachedDomainSeparator;
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32 digest) {
        bytes32 domainSeparator = _cachedDomainSeparator;
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, hex"19_01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            digest := keccak256(ptr, 0x42)
        }
    }

    /**
     * @dev Returns the domain separator without chainId.
     */
    function _chainlessDomainSeparatorV4() internal view returns (bytes32) {
        return _cachedChainlessDomainSeparator;
    }

    function _hashChainlessTypedDataV4(bytes32 structHash) internal view returns (bytes32 digest) {
        bytes32 domainSeparator = _cachedChainlessDomainSeparator;
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, hex"19_01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            digest := keccak256(ptr, 0x42)
        }
    }

    /**
     * @dev Returns the universal domain separator.
     */
    function _universalDomainSeparatorV4() internal view returns (bytes32) {
        return _cachedUniversalDomainSeparator;
    }

    function _hashUniversalTypedDataV4(bytes32 structHash) internal view returns (bytes32 digest) {
        bytes32 domainSeparator = _cachedUniversalDomainSeparator;
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, hex"19_01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            digest := keccak256(ptr, 0x42)
        }
    }
}