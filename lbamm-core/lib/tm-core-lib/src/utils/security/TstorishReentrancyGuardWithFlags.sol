pragma solidity ^0.8.24;

import "../misc/Tstorish.sol";

/**
 * @title TstorishReentrancyGuardWithFlags
 * @dev Variant of {ReentrancyGuard} that uses transient storage with custom flag support.
 *
 * NOTE: This variant only works on networks where EIP-1153 is available.
 */
abstract contract TstorishReentrancyGuardWithFlags is Tstorish {

    // keccak256(abi.encode(uint256(keccak256("storage.TstorishReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    uint256 private constant REENTRANCY_GUARD_STORAGE = 
        0xeff9701f8ef712cda0f707f0a4f48720f142bf7e1bce9d4747c32b4eeb890500;

    uint256 internal constant NO_FLAGS = 0;
    uint256 private constant NOT_ENTERED = 1 << 0;
    uint256 private constant ENTERED = 1 << 1;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() Tstorish() {
        if (!_tstoreInitialSupport) {
            _setTstorish(REENTRANCY_GUARD_STORAGE, NOT_ENTERED);
        }
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore(NO_FLAGS);
        _;
        _nonReentrantAfter();
    }

     /**
     * @dev Prevents a contract from calling itself, directly or indirectly, with custom flags.
     * 
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     *
     * The `flags` parameter can be used to set custom flags for the duration of the
     * transaction.
     * 
     * @param flags Custom flags to set during function execution.
     */
    modifier nonReentrantWithFlags(uint256 flags) {
        _nonReentrantBefore(flags);
        _;
        _nonReentrantAfter();
    }

    function _clearReentrancyGuard() internal {
        _nonReentrantAfter();
    }

    function _setReentrancyFlags(uint256 flags) internal {
        flags = flags & ~(ENTERED | NOT_ENTERED);
        uint256 currentGuard = _getTstorish(REENTRANCY_GUARD_STORAGE) & ENTERED;
        _setTstorish(REENTRANCY_GUARD_STORAGE, currentGuard | flags);
    }

    function _isReentrancyFlagSet(uint256 flag) internal view returns (bool flagSet) {
        return _getTstorish(REENTRANCY_GUARD_STORAGE) & flag > 0;
    }

    function _nonReentrantBefore(uint256 flags) private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_getTstorish(REENTRANCY_GUARD_STORAGE) & ENTERED == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _setTstorish(REENTRANCY_GUARD_STORAGE, ENTERED | flags);
    }

    function _nonReentrantAfter() private {
        _setTstorish(REENTRANCY_GUARD_STORAGE, NOT_ENTERED);
    }

    function _onTstoreSupportActivated() internal virtual override {
        _copyFromStorageToTransient(REENTRANCY_GUARD_STORAGE);
    }
}