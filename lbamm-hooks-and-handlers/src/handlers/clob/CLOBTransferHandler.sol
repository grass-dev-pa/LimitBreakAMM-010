//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./Constants.sol";
import "./DataTypes.sol";
import "./Errors.sol";
import "./interfaces/ICLOBHook.sol";
import "./libraries/CLOBHelper.sol";

import "@limitbreak/lb-amm-core/src/Constants.sol";
import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMM.sol";
import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMMTransferHandler.sol";
import "@limitbreak/lb-amm-core/src/interfaces/hooks/ILimitBreakAMMTokenHook.sol";

import "@limitbreak/tm-core-lib/src/token/erc20/IERC20.sol";
import "@limitbreak/tm-core-lib/src/token/erc20/utils/SafeERC20.sol";
import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";
import "@limitbreak/tm-core-lib/src/utils/misc/StaticDelegateCall.sol";
import "@limitbreak/tm-core-lib/src/utils/security/TstorishReentrancyGuard.sol";
import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

import "@limitbreak/wrapped-native/interfaces/IWrappedNativeExtended.sol";

/**
 * @title  CLOBTransferHandler
 * @author Limit Break, Inc.
 * @notice CLOBTransferHandler is an onchain CLOB that allows order makers to deposit and withdraw
 *         tokens, open and close orders, and have their orders filled by the Limit Break AMM system.
 */
contract CLOBTransferHandler is ILimitBreakAMMTransferHandler, TstorishReentrancyGuard, StaticDelegateCall {
    /// @dev The address of the Limit Break AMM contract that is authorized to call this handler
    address public immutable AMM;

    /// @dev Next order nonce for order creation
    uint256 private nextOrderNonce;

    /// @dev Address of the wrapped native contract for receiving/rewrapping native token
    address private constant WRAPPED_NATIVE = 0x6000030000842044000077551D00cfc6b4005900;

    /// @dev Mapping of maker/depositor balances for each token they deposit
    mapping (address token => mapping (address maker => uint256 balance)) public makerTokenBalance;
    /// @dev Mapping of order book keys to order book storage
    mapping (bytes32 => OrderBook) private orderBooks;
    /// @dev Mapping of order book keys to if they have been initialized.
    mapping (bytes32 => bool) private orderBookKeyInitialized;
    /// @dev Mapping of order book keys to a struct of data represented by the key if it is initialized
    mapping (bytes32 => OrderBookKey) public orderBookKeys;
    
    /// @dev Emitted when tokens are deposited.
    event TokenDeposited(address indexed token, address indexed depositor, uint256 amount);
    /// @dev Emitted when tokens are withdrawn.
    event TokenWithdrawn(address indexed token, address indexed depositor, uint256 amount);
    /// @dev Emitted when an order book is initialized.
    event OrderBookInitialized(bytes32 indexed orderBookKey, address tokenIn, address tokenOut, address hook, uint16 minimumOrderBase, uint8 minimumOrderScale);
    /// @dev Emitted when an order is opened.
    event OrderOpened(address indexed maker, bytes32 indexed orderBookKey, uint256 orderAmount, uint160 sqrtPriceX96, uint256 orderNonce);
    /// @dev Emitted when an order is closed.
    event OrderClosed(address indexed maker, bytes32 indexed orderBookKey, uint256 unfilledInputAmount, uint256 orderNonce);
    /// @dev Emitted when an order book fill is executed. `endingOrderNonce` is the new head order of the order book, if zero the order book has been cleared from the fill.
    event OrderBookFill(bytes32 indexed orderBookKey, uint256 endingOrderNonce, uint256 endingOrderInputRemaining);
    
    constructor(address _AMM) {
        AMM = _AMM;
    }

    /**
     * @notice  Receives native value and redeposits to WNATIVE
     * 
     * @dev     Throws when the sender is not the WNATIVE contract
     */
    receive() external payable {
        if (msg.sender != WRAPPED_NATIVE) revert CLOBTransferHandler__InvalidNativeTransfer();
        IWrappedNativeExtended(WRAPPED_NATIVE).deposit{value: msg.value}();
    }

    /**
     * @notice  Initializes an order book key so that the key can be looked up in the 
     *          public `orderBookKeys` mapping to retrieve the underlying data.
     * 
     * @param tokenIn            Address of the order book's input token.
     * @param tokenOut           Address of the order book's output token.
     * @param hook               Address of the validation hook for the order book.
     * @param minimumOrderBase   Base amount for minimum order book value to be scaled.
     * @param minimumOrderScale  Scale amount for minimum order book value.
     */
    function initializeOrderBookKey(
        address tokenIn,
        address tokenOut,
        address hook,
        uint16 minimumOrderBase,
        uint8 minimumOrderScale
    ) public {
        bytes32 orderBookKey = generateOrderBookKey(
            tokenIn,
            tokenOut,
            generateGroupKey(hook, minimumOrderBase, minimumOrderScale)
        );

        _initializeOrderBookKeyIfNotInitialized(orderBookKey, tokenIn, tokenOut, hook, minimumOrderBase, minimumOrderScale);
    }

    /**
     * @notice  Generates the order book key for an order book based on token pairing and group key.
     * 
     * @param tokenIn   Address of the order book's input token.
     * @param tokenOut  Address of the order book's output token.
     * @param groupKey  Group key to use for the order book - defines hook and minimum order size.
     */
    function generateOrderBookKey(
        address tokenIn,
        address tokenOut,
        bytes32 groupKey
    ) public pure returns (bytes32 orderBookKey) {
        orderBookKey = EfficientHash.efficientHash(
            bytes32(uint256(uint160(tokenIn))),
            bytes32(uint256(uint160(tokenOut))),
            groupKey
        );
    }

    /**
     * @notice  Generates the group key based on validation hook and minimum order size.
     * 
     * @param hook               Address of the validation hook to use for all order books in this group.
     * @param minimumOrderBase   Base amount for minimum order book value to be scaled.
     * @param minimumOrderScale  Scale amount for minimum order book value.
     */
    function generateGroupKey(
        address hook,
        uint16 minimumOrderBase,
        uint8 minimumOrderScale
    ) public pure returns (bytes32 key) {
        key = bytes32(uint256(uint160(hook)) << 96) | bytes32(uint256(minimumOrderBase) << 8) | bytes32(uint256(minimumOrderScale));
    }

    /**
     * @notice Decodes a group key to retrieve the validation hook.
     * 
     * @param groupKey  Group key to decode the validation hook from.
     * 
     * @return hook  Address of the validation hook from the group key.
     */
    function getGroupKeyHook(bytes32 groupKey) public pure returns (address hook) {
        assembly ("memory-safe") {
            hook := shr(96, groupKey)
        }
    }

    /**
     * @notice Decodes a group key to retrieve the minimum order size.
     * 
     * @param groupKey  Group key to decode the minimum order size from.
     * 
     * @return minimumOrder  Minimum order amount for an order using this group.
     */
    function getGroupKeyMinimumOrder(bytes32 groupKey) public pure returns (uint256 minimumOrder) {
        assembly ("memory-safe") {
            minimumOrder := mul(and(shr(8, groupKey), 0xFFFF), exp(10, and(groupKey, 0xFF)))
        }
    }

    /**
     * @notice Decodes a group key to retrieve the minimum order base.
     * 
     * @param groupKey  Group key to decode the minimum order base from.
     * 
     * @return minimumOrderBase  Minimum order base for an order using this group.
     */
    function getGroupKeyMinimumOrderBase(bytes32 groupKey) public pure returns (uint16 minimumOrderBase) {
        assembly ("memory-safe") {
            minimumOrderBase := and(shr(8, groupKey), 0xFFFF)
        }
    }

    /**
     * @notice Decodes a group key to retrieve the minimum order scale.
     * 
     * @param groupKey  Group key to decode the minimum order scale from.
     * 
     * @return minimumOrderScale  Minimum order scale for an order using this group.
     */
    function getGroupKeyMinimumOrderScale(bytes32 groupKey) public pure returns (uint8 minimumOrderScale) {
        assembly ("memory-safe") {
            minimumOrderScale := and(groupKey, 0xFF)
        }
    }

    /**************************************************************/
    /*                        AMM CALLBACK                        */
    /**************************************************************/

    /**
     * @notice  Handles CLOB-based token transfers for Limit Break AMM swap operations by filling CLOB orders
     *          with the output from Limit Break AMM and providing the CLOB order input back.
     * 
     * @dev     Any unfilled output amount is stored transiently to be sent after swap finalization in the AMM.
     * 
     * @dev     Throws when the caller is not the authorized Limit Break AMM contract.
     * @dev     Throws when the transferExtraData is empty.
     * @dev     Throws when transferExtraData cannot be decoded as the expected FillParams struct (solidity panic).
     * @dev     Throws when there is insufficient liquidity in the order book to fill the AMM order.
     * @dev     Throws when there is insufficient output tokens from the AMM to fill the CLOB order.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. CLOB orders are filled starting from lowest price, for orders filling at the same price they are filled FIFO.
     * @dev    2. Maker balances of the output token are updated as their orders fill.
     * @dev    3. Remaining output token is stored transiently to be handled after the swap is finalized in the AMM.
     * @dev    4. The required amount of input tokens has been transferred from the CLOB to the Limit Break AMM.
     * 
     * 
     * @param  executor          The address of the executor of the swap.
     * @param  swapOrder         The swap order details containing deadline, recipient, amount specified, limit amount, and token addresses.
     * @param  amountIn          The actual amount of input tokens required for the swap.
     * @param  amountOut         The actual amount of output tokens that will be received from the swap.
     * @param  exchangeFee       Exchange fee configuration and recipient address.
     * @param  feeOnTop          Additional flat fee configuration and recipient address.
     * @param  transferExtraData Encoded order fill data.
     * 
     * @return callbackData      Callback data to execute after swap finalization, if a refund is required.
     */
    function ammHandleTransfer(
        address executor,
        SwapOrder calldata swapOrder,
        uint256 amountIn,
        uint256 amountOut,
        BPSFeeWithRecipient calldata exchangeFee,
        FlatFeeWithRecipient calldata feeOnTop,
        bytes calldata transferExtraData
    ) external nonReentrant returns (bytes memory callbackData) {
        if (msg.sender != AMM) {
            revert CLOBTransferHandler__CallbackMustBeFromAMM();
        }
        if (transferExtraData.length == 0) {
            revert CLOBTransferHandler__InvalidDataLength();
        }
        if (swapOrder.recipient != address(this)) {
            revert CLOBTransferHandler__HandlerMustBeRecipient();
        }
        if (swapOrder.amountSpecified < 0) {
            revert CLOBTransferHandler__OutputBasedNotAllowed();
        }

        FillCache memory fillCache = FillCache({
            tokenIn: swapOrder.tokenIn,
            tokenOut: swapOrder.tokenOut,
            amountIn: amountIn,
            amountOut: amountOut
        });

        FillParams memory params = abi.decode(transferExtraData, (FillParams));
        bytes32 orderBookKey = generateOrderBookKey(fillCache.tokenIn, fillCache.tokenOut, params.groupKey);

        address hook = getGroupKeyHook(params.groupKey);
        if (hook != address(0)) {
            ICLOBHook(hook).validateExecutor(
                orderBookKey,
                executor,
                swapOrder,
                fillCache.amountIn,
                fillCache.amountOut,
                exchangeFee,
                feeOnTop,
                params.hookData
            );
        }

        uint256 fillOutputRemaining;
        {
            uint256 endingOrderNonce;
            uint256 endingOrderInputRemaining;
            (
                fillOutputRemaining,
                endingOrderNonce,
                endingOrderInputRemaining
            ) = CLOBHelper.fillOrder(
                orderBooks[orderBookKey],
                makerTokenBalance[fillCache.tokenOut],
                fillCache.amountIn,
                fillCache.amountOut
            );
            emit OrderBookFill(orderBookKey, endingOrderNonce, endingOrderInputRemaining);
        }

        if (fillOutputRemaining > 0) {
            if (fillOutputRemaining > params.maxOutputSlippage) {
                revert CLOBTransferHandler__FillOutputExceedsMaxSlippage();
            }
            callbackData = abi.encodeWithSelector(
                CLOBTransferHandler.afterSwapRefund.selector,
                executor,
                fillCache.tokenOut,
                fillOutputRemaining
            );
        }

        bool isError = SafeERC20.safeTransfer(fillCache.tokenIn, AMM, fillCache.amountIn);
        if (isError) {
            revert CLOBTransferHandler__TransferFailed();
        }
    }

    /**
     * @notice  Executes when the handle transfer function has excess tokens received from the AMM that were not
     *          used to fill orders and refunds the tokens to the executor. If the token is wrapped native,
     *          funds will attempt to unwrap to native value to the executor first and fall back to transferring
     *          wrapped native if the unwrap fails.
     * 
     * @dev     Throws when the caller is not the AMM.
     * @dev     Throws when the refund fails to execute.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Transient refund balances are cleared.
     * @dev    2. Refund balance is sent to the executor.
     */
    function afterSwapRefund(address executor, address token, uint256 refundAmount) external {
        if (msg.sender != AMM) {
            revert CLOBTransferHandler__CallbackMustBeFromAMM();
        }

        if (token == WRAPPED_NATIVE) {
            // attempt to withdraw native value directly to executor
            try IWrappedNativeExtended(WRAPPED_NATIVE).withdrawToAccount(executor, refundAmount) {
                // withdraw was successful, return
                return;
            } catch  {
                // withdraw was not successful, continue to transfer WNATIVE
            }
        }
        bool isError = SafeERC20.safeTransfer(token, executor, refundAmount);
        if (isError) {
            revert CLOBTransferHandler__TransferFailed();
        }
    }

    /**************************************************************/
    /*                        CLOB MGMT                           */
    /**************************************************************/

    /**
     * @notice  Deposits funds to the CLOB from the caller for use in opening orders.
     * 
     * @dev     Throws when the amount specified to deposit is zero.
     * @dev     Throws when the transfer fails.
     * @dev     Throws when the CLOB's balance does not increase by the deposit amount.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Deposit token is transferred from the depositor to the CLOB.
     * @dev    2. Depositor's token balance is incremented by the deposit amount.
     * @dev    3. A `TokenDeposited` event is emitted.
     * 
     * @param tokenAddress  Address of the token to deposit to the CLOB.
     * @param amount        Amount of token to deposit.
     */
    function depositToken(
        address tokenAddress,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert CLOBTransferHandler__ZeroDepositAmount();
        }

        uint256 balanceBefore = IERC20(tokenAddress).balanceOf(address(this));
        bool isError = SafeERC20.safeTransferFrom(tokenAddress, msg.sender, address(this), amount);
        if (isError) {
            revert CLOBTransferHandler__TransferFailed();
        }
        uint256 balanceAfter = IERC20(tokenAddress).balanceOf(address(this));
        if (balanceBefore + amount != balanceAfter) {
            revert CLOBTransferHandler__InvalidTransferAmount();
        }

        makerTokenBalance[tokenAddress][msg.sender] += amount;

        emit TokenDeposited(tokenAddress, msg.sender, amount);
    }

    /**
     * @notice  Withdraws the caller's funds from the CLOB.
     * 
     * @dev     Throws when the amount specified to withdraw is zero.
     * @dev     Throws when the caller does not have sufficient balance to withdraw.
     * @dev     Throws when the transfer out fails.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Withdraw token is transferred from the CLOB to the caller.
     * @dev    2. Caller's token balance is decremented by the withdraw amount.
     * @dev    3. A `TokenWithdrawn` event is emitted.
     * 
     * @param tokenAddress  Address of the token to withdraw from the CLOB.
     * @param amount        Amount of token to withdraw.
     */
    function withdrawToken(
        address tokenAddress,
        uint256 amount
    ) external nonReentrant {
        if (amount == 0) {
            revert CLOBTransferHandler__ZeroWithdrawAmount();
        }

        uint256 depositBalance = makerTokenBalance[tokenAddress][msg.sender];
        if (depositBalance < amount) {
            revert CLOBTransferHandler__InsufficientMakerBalance();
        }
        unchecked {
            makerTokenBalance[tokenAddress][msg.sender] = depositBalance - amount;
        }
        bool isError = SafeERC20.safeTransfer(tokenAddress, msg.sender, amount);
        if (isError) {
            revert CLOBTransferHandler__TransferFailed();
        }

        emit TokenWithdrawn(tokenAddress, msg.sender, amount);
    }

    /**
     * @notice  Closes the maker's order in the CLOB.
     * 
     * @dev     Throws when the caller was not the order maker.
     * @dev     Throws when the order has already been closed.
     * @dev     Throws when the order has already been filled.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Order is closed in the order book and order queues updated.
     * @dev    2. Caller's token balance is incremented by the unfilled order amount.
     * @dev    3. A `OrderClosed` event is emitted.
     * 
     * @param tokenIn       Address of the input token of the order.
     * @param tokenOut      Address of the output token of the order.
     * @param sqrtPriceX96  Price the order was placed at.
     * @param orderNonce    The nonce of the order when it was created.
     * @param groupKey      The group key the order was placed with.
     */
    function closeOrder(
        address tokenIn,
        address tokenOut,
        uint160 sqrtPriceX96,
        uint256 orderNonce,
        bytes32 groupKey
    ) external nonReentrant {
        bytes32 orderBookKey = generateOrderBookKey(tokenIn, tokenOut, groupKey);

        uint256 unfilledInputAmount = CLOBHelper.closeOrder(
            orderBooks[orderBookKey],
            msg.sender,
            sqrtPriceX96,
            orderNonce
        );

        makerTokenBalance[tokenIn][msg.sender] += unfilledInputAmount;

        emit OrderClosed(msg.sender, orderBookKey, unfilledInputAmount, orderNonce);
    }

    /**
     * @notice  Opens a new order in the CLOB.
     * 
     * @dev     Will attempt to collect funds from order maker if their existing balance is insufficient.
     * 
     * @dev     Throws when the input and output tokens are the same token.
     * @dev     Throws when the caller does not have sufficient balance to open the order.
     * @dev     Throws when the order does not meet the group minimum.
     * @dev     Throws when the group hook or token hooks revert.
     * @dev     Throws when the order input exceeds a 128 bit value.
     * @dev     Throws when the order price exceeds the minimum or maximum sqrt price value.
     * 
     * @dev    <h4>Postconditions:</h4>
     * @dev    1. Caller's token balance is decremented by the order input amount.
     * @dev    2. Order book key is initialized if this is the first order in the order book.
     * @dev    3. The order is opened in the order book.
     * @dev    4. A `OrderOpened` event is emitted.
     * 
     * @param tokenIn           Address of the input token for the order.
     * @param tokenOut          Address of the output token for the order.
     * @param sqrtPriceX96      Price of the order.
     * @param orderAmount       Amount of input token for the order.
     * @param groupKey          Group key for the order defining the hook and minimum order size.
     * @param hintSqrtPriceX96  Hint for adding the order to the order book's pricing linked lists.
     * @param hookData          Calldata to send with hook calls that are executed when adding to order book.
     * 
     * @return orderNonce  The nonce assigned to the order when opened.
     */
    function openOrder(
        address tokenIn,
        address tokenOut,
        uint160 sqrtPriceX96,
        uint256 orderAmount,
        bytes32 groupKey,
        uint160 hintSqrtPriceX96,
        HooksExtraData calldata hookData
    ) external nonReentrant returns (uint256 orderNonce) {
        if (tokenIn == tokenOut) {
            revert CLOBTransferHandler__CannotPairIdenticalTokens();
        }

        uint256 depositBalance = makerTokenBalance[tokenIn][msg.sender];
        if (depositBalance < orderAmount) {
            // attempt to collect tokens from order maker
            uint256 depositRequired;
            unchecked {
                depositRequired = orderAmount - depositBalance;
            }
            uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));
            bool isError = SafeERC20.safeTransferFrom(tokenIn, msg.sender, address(this), depositRequired);
            if (isError) {
                revert CLOBTransferHandler__InsufficientMakerBalance();
            }
            uint256 balanceAfter = IERC20(tokenIn).balanceOf(address(this));
            if (balanceBefore + depositRequired != balanceAfter) {
                revert CLOBTransferHandler__InvalidTransferAmount();
            }

            emit TokenDeposited(tokenIn, msg.sender, depositRequired);

            // maker's existing balance and shortage will be fully consumed opening this new order, set to zero
            makerTokenBalance[tokenIn][msg.sender] = 0;
        } else {
            unchecked {
                makerTokenBalance[tokenIn][msg.sender] = depositBalance - orderAmount;
            }
        }

        if (orderAmount < getGroupKeyMinimumOrder(groupKey)) {
            revert CLOBTransferHandler__OrderAmountLessThanGroupMinimum();
        }

        bytes32 orderBookKey = generateOrderBookKey(tokenIn, tokenOut, groupKey);
        _initializeOrderBookKeyIfNotInitialized(orderBookKey, tokenIn, tokenOut, groupKey);

        address hook = getGroupKeyHook(groupKey);
        if (hook != address(0)) {
            ICLOBHook(hook).validateMaker(orderBookKey, msg.sender, sqrtPriceX96, orderAmount, hookData.clobHook);
        }

        _enforceTokenHooks(orderBookKey, tokenIn, tokenOut, sqrtPriceX96, orderAmount, hookData);

        CLOBHelper.openOrder(
            orderBooks[orderBookKey],
            orderNonce = nextOrderNonce++,
            msg.sender,
            sqrtPriceX96,
            orderAmount,
            hintSqrtPriceX96
        );

        emit OrderOpened(msg.sender, orderBookKey, orderAmount, sqrtPriceX96, orderNonce);
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
        manifestUri = ""; //TODO: Before final deploy, create permalink for CLOBTransferHandler manifest
    }

    /**
     * @notice  Retrieves the token hook settings for the order book tokens from the AMM and executes
     *          validate handler order hooks if they are enabled for the tokens.
     * 
     * @dev     Throws when a token hook reverts.
     * 
     * @param orderBookKey      The key for the order book the order is being added to.
     * @param tokenIn           Address of the input token.
     * @param tokenOut          Address of the output token.
     * @param sqrtPriceX96      Price the order is being placed at.
     * @param orderAmount       The amount of input token for the order.
     * @param hookData          Calldata to send with hook calls that are executed when adding to order book.
     */
    function _enforceTokenHooks(
        bytes32 orderBookKey,
        address tokenIn,
        address tokenOut,
        uint160 sqrtPriceX96,
        uint256 orderAmount,
        HooksExtraData calldata hookData
    ) internal {
        TokenSettings memory tokenInSettings = ILimitBreakAMM(AMM).getTokenSettings(tokenIn);
        TokenSettings memory tokenOutSettings = ILimitBreakAMM(AMM).getTokenSettings(tokenOut);
        bool validateTokenIn = _isFlagSet(tokenInSettings.packedSettings, TOKEN_SETTINGS_HANDLER_ORDER_VALIDATE_FLAG);
        bool validateTokenOut = _isFlagSet(tokenOutSettings.packedSettings, TOKEN_SETTINGS_HANDLER_ORDER_VALIDATE_FLAG);

        bytes memory handlerOrderParams;
        uint256 amountOut;
        if (validateTokenIn || validateTokenOut) {
            amountOut = CLOBHelper.calculateFixedInput(orderAmount, sqrtPriceX96);
            handlerOrderParams = abi.encode(orderBookKey, sqrtPriceX96);
        }

        if (validateTokenIn) {
            ILimitBreakAMMTokenHook(tokenInSettings.tokenHook).validateHandlerOrder(
                msg.sender,
                true,
                tokenIn,
                tokenOut,
                orderAmount,
                amountOut,
                handlerOrderParams,
                hookData.tokenInHook
            );
        }

        if (validateTokenOut) {
            ILimitBreakAMMTokenHook(tokenOutSettings.tokenHook).validateHandlerOrder(
                msg.sender,
                false,
                tokenIn,
                tokenOut,
                orderAmount,
                amountOut,
                handlerOrderParams,
                hookData.tokenOutHook
            );
        }
    }

    /**
     * @notice  Checks if the order book key has been initialized and initializes if not.
     * 
     * @param orderBookKey  The key for the order book.
     * @param tokenIn       The input token for the order book.
     * @param tokenOut      The output token for the order book.
     * @param groupKey      Group key to decode the validation hook and minimum order data from.
     */
    function _initializeOrderBookKeyIfNotInitialized(
        bytes32 orderBookKey,
        address tokenIn,
        address tokenOut,
        bytes32 groupKey
    ) internal {
        if (!orderBookKeyInitialized[orderBookKey]) {
            _initializeOrderBookKey(
                orderBookKey,
                tokenIn,
                tokenOut,
                getGroupKeyHook(groupKey),
                getGroupKeyMinimumOrderBase(groupKey),
                getGroupKeyMinimumOrderScale(groupKey)
            );
        }
    }

    /**
     * @notice  Checks if the order book key has been initialized and initializes if not.
     * 
     * @param orderBookKey       The key for the order book.
     * @param tokenIn            The input token for the order book.
     * @param tokenOut           The output token for the order book.
     * @param hook               Address of the validation hook for the order book.
     * @param minimumOrderBase   Base amount for minimum order book value to be scaled.
     * @param minimumOrderScale  Scale amount for minimum order book value.
     */
    function _initializeOrderBookKeyIfNotInitialized(
        bytes32 orderBookKey,
        address tokenIn,
        address tokenOut,
        address hook,
        uint16 minimumOrderBase,
        uint8 minimumOrderScale
    ) internal {
        if (!orderBookKeyInitialized[orderBookKey]) {
            _initializeOrderBookKey(
                orderBookKey,
                tokenIn,
                tokenOut,
                hook,
                minimumOrderBase,
                minimumOrderScale
            );
        }
    }

    /**
     * @notice  Initializes the order book key in the order book key mappings, marks as initialized
     *          and emits an `OrderBookInitialized` event.
     * 
     * @dev     Throws when the minimum order base is zero.
     * @dev     Throws when the minimum order scale exceeds the maximum value allowed.
     * 
     * @param orderBookKey       The key for the order book.
     * @param tokenIn            The input token for the order book.
     * @param tokenOut           The output token for the order book.
     * @param hook               Address of the validation hook for the order book.
     * @param minimumOrderBase   Base amount for minimum order book value to be scaled.
     * @param minimumOrderScale  Scale amount for minimum order book value.
     */
    function _initializeOrderBookKey(
        bytes32 orderBookKey,
        address tokenIn,
        address tokenOut,
        address hook,
        uint16 minimumOrderBase,
        uint8 minimumOrderScale
    ) internal {
        if (minimumOrderBase == 0) {
            revert CLOBTransferHandler__GroupMinimumCannotBeZero();
        }
        if (minimumOrderScale > MAXIMUM_ORDER_SCALE) {
            revert CLOBTransferHandler__MinimumOrderScaleExceedsMaximum();
        }

        orderBookKeys[orderBookKey] = OrderBookKey({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            hook: hook,
            minimumOrderBase: minimumOrderBase,
            minimumOrderScale: minimumOrderScale
        });
        orderBookKeyInitialized[orderBookKey] = true;

        emit OrderBookInitialized(orderBookKey, tokenIn, tokenOut, hook, minimumOrderBase, minimumOrderScale);
    }

    /**
     * @dev Checks if a specific flag is set in a packed flag value using bitwise operations.
     *
     * @dev Uses bitwise AND operation to test if the specified flag bit is set in the flag value.
     *      Returns true if the flag is present, false otherwise.
     *
     * @param  flagValue The packed value containing multiple flags.
     * @param  flag      The specific flag bit to check.
     * @return flagSet   True if the flag is set, false otherwise.
     */
    function _isFlagSet(uint256 flagValue, uint256 flag) internal pure returns (bool flagSet) {
        flagSet = (flagValue & flag) != 0;
    }
}