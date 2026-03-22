//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../DataTypes.sol";

/**
 * @title  ILimitBreakAMMTransferHandler
 * @author Limit Break, Inc.
 * @notice Interface definition for transfer handlers to be interacted with from the 
 *         core AMM. Transfer handlers are modular components for the AMM to extend 
 *         the ways that input tokens to swaps can be supplied.
 */
interface ILimitBreakAMMTransferHandler {
    /// @dev Emitted when the transfer handler manifest URI is updated.
    event TransferHandlerManifestUriUpdated(string uri);

    /**
     * @notice  Called by AMM core during swap finalization to handle the transfer of input tokens for the swap.
     * 
     * @dev     Allows for developers to expand ways that tokens may be transferred to the AMM to settle swaps
     *          while retaining full context of the swap executor, swap details and fees.
     * 
     * @param executor           Address of the order executor.
     * @param swapOrder          Original swap order parameters including tokens and limits.
     * @param amountIn           Amount of input tokens required for the order.
     * @param amountOut          Amount of output tokens that will be filled on the order.
     * @param exchangeFee        Exchange fee configuration and recipient.
     * @param feeOnTop           Additional flat fee configuration and recipient.
     * @param transferExtraData  Arbitrary calldata passed to the transfer handler.
     * 
     * @return callbackData      ABI encoded callback data, including function selector, to execute on the transfer handler after swap finalization.
     */
    function ammHandleTransfer(
        address executor,
        SwapOrder calldata swapOrder,
        uint256 amountIn,
        uint256 amountOut,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        bytes calldata transferExtraData
    ) external returns (bytes memory callbackData);

    /**
     * @notice  Returns the manifest URI for the transfer handler to provide app integrations with
     *          information necessary to process transactions that utilize the transfer handler.
     * 
     * @dev     Hook developers **MUST** emit a `TransferHandlerManifestUriUpdated` event if the URI
     *          changes.
     * 
     * @return  manifestUri  The URI for the handler manifest data. 
     */
    function transferHandlerManifestUri() external view returns(string memory manifestUri);
}
