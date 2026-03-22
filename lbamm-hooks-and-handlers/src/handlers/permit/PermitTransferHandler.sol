//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./Constants.sol";
import "./DataTypes.sol";
import "./Errors.sol";
import "../interfaces/ITransferHandlerExecutorValidation.sol";

import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMMTransferHandler.sol";

import "@limitbreak/permit-c/DataTypes.sol";
import "@limitbreak/permit-c/interfaces/IPermitC.sol";

import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";
import "@limitbreak/tm-core-lib/src/utils/cryptography/EIP712.sol";
import "@limitbreak/tm-core-lib/src/utils/cryptography/Signatures.sol";
import "@limitbreak/tm-core-lib/src/utils/math/FullMath.sol";
import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  PermitTransferHandler
 * @author Limit Break, Inc.
 * @notice Handles permit-based token transfers for the Limit Break AMM system using the PermitC advanced permit system.
 *         This contract acts as a callback handler that processes both fill-or-kill and partial-fill permit transfers
 *         to prevent overpayment and ensure secure token transfers during swaps.
 *
 * @dev    This contract implements ILimitBreakAMMTransferHandler and is designed to be called exclusively by the 
 *         Limit Break AMM contract during swap operations. It integrates with the PermitC system which extends beyond
 *         standard EIP-2612 to provide advanced permit functionality including partial fills, additional data validation,
 *         and cross-token-type support (ERC20, ERC721, ERC1155).
 */
contract PermitTransferHandler is ILimitBreakAMMTransferHandler, EIP712 {
    /// @notice The address of the Limit Break AMM contract that is authorized to call this handler
    address public immutable AMM;

    /// @dev EIP-712 typehash for permit transfers with additional swap data validation
    bytes32 private immutable PERMITTED_TRANSFER_APPROVAL_TYPEHASH;

    /// @dev EIP-712 typehash for permit orders with additional swap data validation
    bytes32 private immutable PERMITTED_ORDER_APPROVAL_TYPEHASH;

    /// @dev Mapping of cosigners to if they have been destroyed.
    mapping (address => bool) public destroyedCosigners;
    
    /// @dev Bitmap of cosigners to their consumed nonces for efficient nonce consumption.
    mapping(address => mapping(uint256 => uint256)) private cosignerConsumedNonces;

    /// @dev Emitted when a cosigner has self destructed.
    event DestroyedCosigner(address cosigner);

    /// @dev Emitted when a cosignature nonce has been consumed.
    event CosignatureNonceConsumed(address indexed cosigner, uint256 nonce);

    constructor(address _AMM) EIP712("PermitTransferHandler", "1") {
        AMM = _AMM;

        PERMITTED_TRANSFER_APPROVAL_TYPEHASH = keccak256(
            bytes.concat(
                bytes(PERMITTED_TRANSFER_APPROVAL_TYPEHASH_STUB),
                bytes(PERMITTED_APPROVAL_TYPEHASH_EXTRADATA_STUB),
                bytes(SWAP_TYPEHASH_STUB)
            )
        );

        PERMITTED_ORDER_APPROVAL_TYPEHASH = keccak256(
            bytes.concat(
                bytes(PERMITTED_ORDER_APPROVAL_TYPEHASH_STUB),
                bytes(PERMITTED_APPROVAL_TYPEHASH_EXTRADATA_STUB),
                bytes(SWAP_TYPEHASH_STUB)
            )
        );
    }

    /**
     * @notice  Handles permit-based token transfers for Limit Break AMM swap operations.
     * 
     * @dev     This function supports two permit types: fill-or-kill (atomic) and partial-fill permits.
     *          The function decodes the permit type from the first byte of transferExtraData and routes to the
     *          appropriate permit execution function. All transfers are validated against permit parameters to
     *          prevent overpayment and ensure security.
     * 
     * @dev     Throws when the caller is not the authorized Limit Break AMM contract.
     * @dev     Throws when the transferExtraData is empty.
     * @dev     Throws when the permit type is invalid (not FILL_OR_KILL_PERMIT or PARTIAL_FILL_PERMIT).
     * @dev     Throws when transferExtraData cannot be decoded as the expected permit structure (solidity panic).
     * @dev     Throws when the permit transfer execution fails.
     * @dev     If the permit is a partial fill permit -
     * @dev         Throws when the permit swap mode doesn't match the order swap mode (input-based vs output-based).
     * @dev         Throws when a partial fill exceeds the maximum allowed input for the given output.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. The required amount of input tokens has been transferred from the permit holder to the Limit Break AMM.
     * @dev    2. For fill-or-kill permits, the permit nonce has been consumed in the PermitC contract.
     * @dev    3. For partial fill permits, the order fill state has been updated in the PermitC contract.
     * @dev    4. The permit signature has been validated against the additional data hash containing swap parameters.
     * @dev    5. The permit expiration has been validated against the current block timestamp.
     * 
     * @param  executor          The address of the executor of the swap.
     * @param  swapOrder         The swap order details containing deadline, recipient, amount specified, limit amount, and token addresses.
     * @param  amountIn          The actual amount of input tokens required for the swap.
     * @param  amountOut         The actual amount of output tokens that will be received from the swap.
     * @param  exchangeFee       Exchange fee configuration and recipient address.
     * @param  feeOnTop          Additional flat fee configuration and recipient address.
     * @param  transferExtraData Encoded permit data with first byte as permit type and remaining bytes as permit details.
     */
    function ammHandleTransfer(
        address executor,
        SwapOrder calldata swapOrder,
        uint256 amountIn,
        uint256 amountOut,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        bytes calldata transferExtraData
    ) external returns (bytes memory) {
        if (msg.sender != AMM) {
            revert PermitTransferHandler__CallbackMustBeFromAMM();
        }
        if (transferExtraData.length == 0) {
            revert PermitTransferHandler__InvalidDataLength();
        }

        bytes1 permitType = bytes1(transferExtraData[0:1]);

        if (permitType == FILL_OR_KILL_PERMIT) {
            FillOrKillPermitTransfer memory permitData = abi.decode(transferExtraData[1:], (FillOrKillPermitTransfer));

            _executeFillOrKillPermit(executor, swapOrder, amountIn, amountOut, exchangeFee, feeOnTop, permitData);
        } else if (permitType == PARTIAL_FILL_PERMIT) {
            PartialFillPermitTransfer memory permitData = abi.decode(transferExtraData[1:], (PartialFillPermitTransfer));

            _executePartialFillPermit(executor, swapOrder, amountIn, amountOut, exchangeFee, feeOnTop, permitData);
        } else {
            revert PermitTransferHandler__InvalidPermitType();
        }
    }

    /**
     * @notice Allows a cosigner to destroy itself, never to be used again.  This is a fail-safe in case of a failure
     *         to secure the co-signer private key in a Web2 co-signing service.  In case of suspected cosigner key
     *         compromise, or when a co-signer key is rotated, the cosigner MUST destroy itself to prevent past listings 
     *         that were cancelled off-chain from being used by a malicious actor.
     *
     * @dev    Throws when the cosigner did not sign an authorization to self-destruct.
     *
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. The cosigner can never be used to co-sign orders again.
     * @dev    2. A `DestroyedCosigner` event has been emitted.
     *
     * @param  cosigner  The address of the cosigner to destroy.
     * @param  signature The signature of the cosigner authorizing the destruction of itself.
     */
    function destroyCosigner(address cosigner, bytes calldata signature) external {
        bytes32 digest = _hashUniversalTypedDataV4(EfficientHash.efficientHash(
            COSIGNER_SELF_DESTRUCT_TYPEHASH,
            bytes32(uint256(uint160(cosigner)))
        ));

        Signatures.verifyCalldata(signature, digest, cosigner);

        destroyedCosigners[cosigner] = true;
        emit DestroyedCosigner(cosigner);
    }

    /**
     * @notice  Checks if the cosigner's nonce has been consumed.
     * 
     * @param cosigner   Address of the cosigner to check nonce consumption of. 
     * @param nonce      Nonce to check if it has been consumed.
     * 
     * @return consumed  True if the nonce has been consumed.
     */
    function isCosignerNonceConsumed(address cosigner, uint256 nonce) external view returns (bool consumed) {
        consumed = cosignerConsumedNonces[cosigner][nonce >> NONCE_TO_BUCKET_SHIFT] >> uint8(nonce) & ONE == ONE;
    }

    /**
     * @notice  Returns the manifest URI for the transfer handler to provide app integrations with
     *          information necessary to process transactions that utilize the transfer handler.
     * 
     * @dev     Hook developers **MUST** emit a `TransferHandlerManifestUriUpdated` event if the URI
     *          changes.
     * 
     * @return  manifestUri  The URI for the handler manifest data. 
     */
    function transferHandlerManifestUri() external pure returns(string memory manifestUri) {
        manifestUri = ""; //TODO: Before final deploy, create permalink for PermitTransferHandler manifest
    }

    /**
     * @dev   Executes a fill-or-kill permit transfer where the entire permit amount must be used atomically.
     *
     * @dev    Throws when the PermitC contract returns an error during permit execution.
     *
     * @dev    This function constructs the additional data hash for signature verification and calls the PermitC
     *         contract to execute the transfer with additional data validation. The additional data hash includes 
     *         swap-specific parameters to prevent signature replay attacks and ensure the permit is only 
     *         valid for the specific swap parameters.
     *
     * @param  executor     The address of the executor of the swap.
     * @param  swapOrder    The swap order details used for additional data hash construction.
     * @param  amountIn     The exact amount of input tokens to transfer.
     * @param  amountOut    The actual amount of output tokens that will be received.
     * @param  exchangeFee  The exchange fee details included in the additional data hash.
     * @param  feeOnTop     The additional flat fee configuration and recipient address.
     * @param  permitData   The decoded fill-or-kill permit data containing processor, nonce, amounts, expiration, and signature.
     */
    function _executeFillOrKillPermit(
        address executor,
        SwapOrder calldata swapOrder,
        uint256 amountIn,
        uint256 amountOut,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        FillOrKillPermitTransfer memory permitData
    ) internal {
        if (swapOrder.amountSpecified < 0) {
            if (uint256(-swapOrder.amountSpecified) != amountOut) {
                revert PermitTransferHandler__FillOrKillPermitOrderNotFilled();
            }
        } else {
            if (uint256(swapOrder.amountSpecified) != amountIn) {
                revert PermitTransferHandler__FillOrKillPermitOrderNotFilled();
            }
        }
        
        bytes32 additionalDataHash = EfficientHash.efficientHashTenStep2(
            EfficientHash.efficientHashTenStep1(
                SWAP_TYPEHASH,
                bytes32(uint256(FALSE)),
                bytes32(uint256(uint160(swapOrder.recipient))),
                bytes32(uint256(swapOrder.amountSpecified)),
                bytes32(swapOrder.limitAmount),
                bytes32(uint256(uint160(swapOrder.tokenOut))),
                bytes32(uint256(uint160(exchangeFee.recipient))),
                bytes32(uint256(exchangeFee.BPS))
            ),
            bytes32(uint256(uint160(permitData.cosigner))),
            bytes32(uint256(uint160(permitData.hook)))
        );

        _validateCosignature(
            executor,
            permitData.cosigner,
            permitData.cosignatureExpiration,
            FILL_OR_KILL_COSIGNATURE_NONCE,
            permitData.cosignature,
            keccak256(permitData.signature)
        );

        _validateHook(
            permitData.hook,
            additionalDataHash,
            executor,
            swapOrder,
            amountIn,
            amountOut,
            exchangeFee,
            feeOnTop,
            permitData.hookData
        );

        bool isError = IPermitC(permitData.permitProcessor).permitTransferFromWithAdditionalDataERC20(
            swapOrder.tokenIn,
            permitData.nonce,
            permitData.permitAmount,
            permitData.expiration,
            permitData.from,
            AMM,
            amountIn,
            additionalDataHash,
            PERMITTED_TRANSFER_APPROVAL_TYPEHASH,
            permitData.signature
        );

        if (isError) {
            revert PermitTransferHandler__PermitTransferFailed();
        }
    }

    /**
     * @notice Executes a partial fill permit transfer where only a portion of the permitted amount may be used.
     *
     * @dev    This function handles advanced permit transfers that support partial fills, allowing users to 
     *         authorize a maximum amount while only consuming what's needed for the specific swap. The function 
     *         validates that the swap mode (input-based vs output-based) matches the permit mode and calculates 
     *         the maximum allowed input based on the proportional relationship between the permit parameters 
     *         and actual swap parameters.
     *
     * @dev    For output-based swaps (negative amountSpecified), the permit must also be output-based 
     *         (negative permitAmountSpecified) and uses permitLimitAmount as the permit amount. For input-based 
     *         swaps (positive amountSpecified), the permit must also be input-based (positive permitAmountSpecified) 
     *         and uses permitAmountSpecified as the permit amount.
     *
     * @dev    Throws when the permit swap mode doesn't match the order swap mode (input-based vs output-based).
     * @dev    Throws when the partial fill exceeds the maximum allowed input for the given output ratio.
     *
     * @param  executor     The address of the executor of the swap.
     * @param  swapOrder    The swap order details used for validation and additional data hash construction.
     * @param  amountIn     The actual amount of input tokens required for the swap.
     * @param  amountOut    The actual amount of output tokens that will be received.
     * @param  exchangeFee  The exchange fee details included in the additional data hash.
     * @param  feeOnTop     The additional flat fee configuration and recipient address.
     * @param  permitData   The decoded partial fill permit data containing amounts, limits, salt, expiration, and signature.
     */
    function _executePartialFillPermit(
        address executor,
        SwapOrder calldata swapOrder,
        uint256 amountIn,
        uint256 amountOut,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        PartialFillPermitTransfer memory permitData
    ) internal {
        bytes32 additionalDataHash;
        uint256 permitAmount;
        if (swapOrder.amountSpecified < 0) {
            if (permitData.permitAmountSpecified < 0) {
                permitAmount = permitData.permitLimitAmount;
                uint256 maxAmountIn = FullMath.mulDiv(
                    permitData.permitLimitAmount,
                    amountOut,
                    uint256(-permitData.permitAmountSpecified)
                );
                if (amountIn > maxAmountIn) {
                    revert PermitTransferHandler__PartialFillExceedsMaximumInputForOutput();
                }
            } else {
                revert PermitTransferHandler__PermitSwapInputOutputModeMismatch();
            }
        } else {
            if (permitData.permitAmountSpecified > 0) {
                permitAmount = uint256(permitData.permitAmountSpecified);
                uint256 maxAmountIn = FullMath.mulDiv(
                    uint256(permitData.permitAmountSpecified),
                    amountOut,
                    permitData.permitLimitAmount
                );
                if (amountIn > maxAmountIn) {
                    revert PermitTransferHandler__PartialFillExceedsMaximumInputForOutput();
                }
            } else {
                revert PermitTransferHandler__PermitSwapInputOutputModeMismatch();
            }
        }
        additionalDataHash = EfficientHash.efficientHashTenStep2(
            EfficientHash.efficientHashTenStep1(
                SWAP_TYPEHASH,
                bytes32(uint256(TRUE)),
                bytes32(uint256(uint160(swapOrder.recipient))),
                bytes32(uint256(permitData.permitAmountSpecified)),
                bytes32(permitData.permitLimitAmount),
                bytes32(uint256(uint160(swapOrder.tokenOut))),
                bytes32(uint256(uint160(exchangeFee.recipient))),
                bytes32(uint256(exchangeFee.BPS))
            ),
            bytes32(uint256(uint160(permitData.cosigner))),
            bytes32(uint256(uint160(permitData.hook)))
        );

        _validateCosignature(
            executor,
            permitData.cosigner,
            permitData.cosignatureExpiration,
            permitData.cosignatureNonce,
            permitData.cosignature,
            keccak256(permitData.signature)
        );

        _validateHook(
            permitData.hook,
            additionalDataHash,
            executor,
            swapOrder,
            amountIn,
            amountOut,
            exchangeFee,
            feeOnTop,
            permitData.hookData
        );

        (,bool isError) = IPermitC(permitData.permitProcessor).fillPermittedOrderERC20(
            permitData.signature,
            OrderFillAmounts({
                orderStartAmount: permitAmount,
                requestedFillAmount: amountIn,
                minimumFillAmount: amountIn
            }),
            swapOrder.tokenIn,
            permitData.from,
            AMM,
            permitData.salt,
            uint48(permitData.expiration),
            additionalDataHash,
            PERMITTED_ORDER_APPROVAL_TYPEHASH
        );

        if (isError) {
            revert PermitTransferHandler__PermitTransferFailed();
        }
    }

    /**
     * @notice  Validates the cosignature on a permit order.
     * 
     * @dev     Returns if cosigner is the zero address.
     * @dev     Throws if the cosignature is expired.
     * @dev     Throws if the cosigner has been destroyed.
     * @dev     Throws if the cosignature does not recover to the cosigner address.
     * @dev     Throws if the cosignature nonce has been previously consumed.
     * 
     * @param executor               The address of the executor of the swap.
     * @param cosigner               The address of the cosigner for the permit.
     * @param cosignatureExpiration  The timestamp the cosignature expires.
     * @param cosignatureNonce       The nonce for the cosignature to prevent reuse.
     * @param cosignature            Cosignature data in bytes.
     * @param permitSignatureHash    Hash of the permit signature.
     */
    function _validateCosignature(
        address executor,
        address cosigner,
        uint256 cosignatureExpiration,
        uint256 cosignatureNonce,
        bytes memory cosignature,
        bytes32 permitSignatureHash
    ) internal {
        if (cosigner == address(0)) {
            return;
        }
        if (cosignatureExpiration < block.timestamp) {
            revert PermitTransferHandler__CosignatureExpired();
        }
        if (destroyedCosigners[cosigner]) {
            revert PermitTransferHandler__CosignerDestroyed();
        }
        if (cosignatureNonce != REUSABLE_COSIGNATURE_NONCE) {
            _consumeCosignerNonce(cosigner, cosignatureNonce);
        }

        bytes32 digest = _hashTypedDataV4(
            EfficientHash.efficientHash(
                COSIGNATURE_TYPEHASH,
                permitSignatureHash,
                bytes32(cosignatureExpiration),
                bytes32(cosignatureNonce),
                bytes32(uint256(uint160(executor)))
            )
        );
        
        Signatures.verifyMemory(cosignature, digest, cosigner);
    }

    /**
     * @notice Consumes a cosignature nonce.
     * 
     * @dev    Throws when the nonce has already been consumed.
     * 
     * @param cosigner The cosigner account to consume `nonce` of.
     * @param nonce    The nonce to consume.
     */
    function _consumeCosignerNonce(address cosigner, uint256 nonce) internal {
        unchecked {
            if (uint256(cosignerConsumedNonces[cosigner][nonce >> NONCE_TO_BUCKET_SHIFT] ^= (ONE << uint8(nonce))) & 
                (ONE << uint8(nonce)) == ZERO) {
                revert PermitTransferHandler__CosignatureNonceAlreadyConsumed();
            }
        }

        emit CosignatureNonceConsumed(cosigner, nonce);
    }

    /**
     * @notice  Calls the hook's validate executor function if the hook address is non-zero.
     * 
     * @dev     Returns without a call if the hook address is zero.
     * @dev     Throws if the call to the hook reverts.
     * 
     * @param hook                Address of the hook for the permit.
     * @param additionalDataHash  Hash of the permit swap data.
     * @param executor            The address of the executor of the swap.
     * @param swapOrder           The swap order details containing deadline, recipient, amount specified, limit amount, and token addresses.
     * @param amountIn            Amount of input token for the swap.
     * @param amountOut           Amount of output token for the swap.
     * @param exchangeFee         Exchange fee configuration and recipient address.
     * @param feeOnTop            Additional flat fee configuration and recipient address.
     * @param hookData            Arbitrary calldata provided with the swap to validate.
     */
    function _validateHook(
        address hook,
        bytes32 additionalDataHash,
        address executor,
        SwapOrder calldata swapOrder,
        uint256 amountIn,
        uint256 amountOut,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        bytes memory hookData
    ) internal {
        if (hook != address(0)) {
            ITransferHandlerExecutorValidation(hook).validateExecutor(
                additionalDataHash,
                executor,
                swapOrder,
                amountIn,
                amountOut,
                exchangeFee,
                feeOnTop,
                hookData
            );
        }
    }
}
