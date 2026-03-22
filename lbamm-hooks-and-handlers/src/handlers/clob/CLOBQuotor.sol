//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./Constants.sol";
import "./DataTypes.sol";
import "./Errors.sol";
import "./interfaces/ICLOBHook.sol";
import "./libraries/CLOBHelper.sol";

import "@limitbreak/tm-core-lib/src/utils/misc/StaticDelegateCall.sol";
import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  CLOBQuotor
 * @author Limit Break, Inc.
 * @notice CLOB Quoter utilizes static delegate calls through CLOBTransferHandler to perform calculations
 *         using state data from the CLOBTransferHandler contract.
 */
contract CLOBQuotor {
    /// @dev The address of the CLOB transfer handler contract that quotes will be calculated from.
    address private immutable CLOB_HANDLER;

    // Match storage layout with CLOBTransferHandler for static delegatecalls.

    /// @dev Next order nonce for order creation
    uint256 private nextOrderNonce;

    /// @dev Address of the wrapped native contract for receiving/rewrapping native token
    address private constant WRAPPED_NATIVE = 0x6000030000842044000077551D00cfc6b4005900;

    /// @dev Mapping of maker/depositor balances for each token they deposit
    mapping (address token => mapping (address maker => uint256 balance)) private makerTokenBalance;
    /// @dev Mapping of order book keys to order book storage
    mapping (bytes32 => OrderBook) private orderBooks;
    /// @dev Mapping of order book keys to if they have been initialized.
    mapping (bytes32 => bool) private orderBookKeyInitialized;
    /// @dev Mapping of order book keys to a struct of data represented by the key if it is initialized
    mapping (bytes32 => OrderBookKey) private orderBookKeys;

    constructor(address _clobTransferHandler) {
        CLOB_HANDLER = _clobTransferHandler;
    }

    /**
     * @notice  Returns the current input amount remaining for a price in an order book.
     * 
     * @param orderBookKey  The key for the order book to get the current order input amount remaining from.
     * @param sqrtPriceX96  The price to get the order input amount remaining from.
     * 
     * @return inputAmountRemaining  The amount of input remaining for the first order for the price in an order book.
     */
    function quoteGetInputAmountRemaining(bytes32 orderBookKey, uint160 sqrtPriceX96) external view returns (uint256 inputAmountRemaining) {
        (inputAmountRemaining) = abi.decode(
            StaticDelegateCall(CLOB_HANDLER).initiateStaticDelegateCall(
                address(this),
                abi.encodeWithSelector(
                    this.processQuoteGetInputAmountRemaining.selector,
                    orderBookKey,
                    sqrtPriceX96
                )
            ),
            (uint256)
        );
    }

    /**
     * @notice  Returns the current price for an order book.
     * 
     * @param orderBookKey  The key for the order book to get the current price from.
     * 
     * @return currentPriceX96  The current lowest price in the order book.
     */
    function quoteGetCurrentPrice(bytes32 orderBookKey) external view returns (uint160 currentPriceX96) {
        (currentPriceX96) = abi.decode(
            StaticDelegateCall(CLOB_HANDLER).initiateStaticDelegateCall(
                address(this),
                abi.encodeWithSelector(
                    this.processQuoteGetCurrentPrice.selector,
                    orderBookKey
                )
            ),
            (uint160)
        );
    }

    /**
     * @notice  This function is to be delegate called by the CLOBTransferHandler contract. Use `quoteGetInputAmountRemaining`
     *          for external calls to the quoter contract.
     * 
     * @param orderBookKey  The key for the order book to get the current order input amount remaining from.
     * @param sqrtPriceX96  The price to get the order input amount remaining from.
     * 
     * @return inputAmountRemaining  The amount of input remaining for the first order for the price in an order book.
     */
    function processQuoteGetInputAmountRemaining(bytes32 orderBookKey, uint160 sqrtPriceX96) external view returns (uint256 inputAmountRemaining) {
        inputAmountRemaining = orderBooks[orderBookKey].priceOrderBucket[sqrtPriceX96].inputAmountRemaining;
    }

    /**
     * @notice  This function is to be delegate called by the CLOBTransferHandler contract. Use `quoteGetCurrentPrice`
     *          for external calls to the quoter contract.
     * 
     * @param orderBookKey  The key for the order book to get the current price from.
     * 
     * @return currentPriceX96  The current lowest price in the order book.
     */
    function processQuoteGetCurrentPrice(bytes32 orderBookKey) external view returns (uint160 currentPriceX96) {
        currentPriceX96 = orderBooks[orderBookKey].currentPrice;
    }
}