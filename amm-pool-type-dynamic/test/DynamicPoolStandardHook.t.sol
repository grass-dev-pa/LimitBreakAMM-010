pragma solidity ^0.8.24;

import "@limitbreak/lb-amm-hooks-and-handlers/test/hooks/AMMStandardHook.t.sol";
import "./DynamicPool.t.sol";

contract DynamicPoolStandardHookTest is DynamicPoolTest, AMMStandardHookTest {
    address currency2Owner;
    address currency3Owner;

    function setUp() public virtual override(DynamicPoolTest, AMMStandardHookTest) {
        super.setUp();

        currency2Owner = currency2.owner();
        currency3Owner = currency3.owner();

        changePrank(currency2Owner);
        currency2.transferOwnership(address(909_090_909));
        currency3.transferOwnership(address(909_090_908));

        currency2Owner = address(909_090_909);
        currency3Owner = address(909_090_908);

        changePrank(currency2Owner);
        _setTokenSettings(
            address(currency2),
            address(standardHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: true,
                addLiquidityHook: true,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: true,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: false
            }),
            bytes4(0)
        );

        changePrank(currency3Owner);
        _setTokenSettings(
            address(currency3),
            address(standardHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: true,
                addLiquidityHook: true,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: true,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: false
            }),
            bytes4(0)
        );

        HookTokenSettings memory emptySettings;
        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), emptySettings, hooksToSync, bytes4(0));
        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), emptySettings, hooksToSync, bytes4(0));
    }

    function test_validateTokenTransferFailure() public {
        changePrank(brokenTokenOwner);
        _setTokenSettings(
            address(brokenToken0),
            address(standardHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: true,
                addLiquidityHook: true,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: true,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: false
            }),
            bytes4(0)
        );

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory hookSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 100,
            tokenFeeSellBPS: 100,
            pairedFeeBuyBPS: 100,
            pairedFeeSellBPS: 100,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), hookSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(
            brokenTokenOwner, address(brokenToken0), hookSettings, hooksToSync, bytes4(0)
        );

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency2),
            token1: address(brokenToken0),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(brokenToken0), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency2),
            tokenOut: address(brokenToken0)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );

        {
            brokenToken0.setBroken(true);

            uint256 tokensOwed = amm.getHookFeesOwedByToken(address(brokenToken0), address(brokenToken0));
            _collectHookFeesByToken(
                ERC20Mock(address(brokenToken0)).owner(),
                address(brokenToken0),
                address(brokenToken0),
                ERC20Mock(address(brokenToken0)).owner(),
                tokensOwed,
                bytes4(LBAMM__TransferHookFeeTransferFailed.selector)
            );
        }

        brokenToken0.setBroken(false);

        {
            brokenToken0.setBroken(true);

            changePrank(alice);
            dynamicParams.liquidityChange = -dynamicParams.liquidityChange;
            _removeDynamicLiquidityWithTokensOwed(
                dynamicParams,
                liquidityParams,
                _emptyLiquidityHooksExtraData(),
                alice,
                bytes4(0)
            );

            address[] memory tokens = new address[](1);
            tokens[0] = address(brokenToken0);
            _collectTokensOwed(alice, tokens, bytes4(LBAMM__TokenOwedTransferFailed.selector));
        }
    }

    function test_createPool_poolTypeWL() public {
        uint256 listId = _executeCreatePoolTypeWhitelist(address(this), "newWL", bytes4(0));
        address[] memory poolTypes = new address[](1);
        poolTypes[0] = address(dynamicPool);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeUpdatePoolTypeWhitelist(address(this), listId, poolTypes, true, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: uint56(listId),
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));
    }

    function test_AUDITM01_createPool_pairTokenWL() public {
        uint256 listId = _executeCreatePairTokenWhitelist(address(this), "newWL", bytes4(0));
        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(currency3);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeUpdatePairTokenWhitelist(address(this), listId, pairTokens, true, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: uint56(listId),
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));
    }

    function test_createPool_revert_poolTypeNotWL() public {
        uint256 listId = _executeCreatePoolTypeWhitelist(address(this), "newWL", bytes4(0));
        address[] memory poolTypes = new address[](1);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeUpdatePoolTypeWhitelist(address(this), listId, poolTypes, true, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: uint56(listId),
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(
            details,
            10,
            1_120_455_419_495_722_798_374_638_764_549_163,
            bytes4(AMMStandardHook__PoolTypeNotAllowed.selector)
        );
    }

    function test_createPool_revert_minFeeNotMet() public {
        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 1000,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 999,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(
            details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(AMMStandardHook__PoolFeeTooLow.selector)
        );
    }

    function test_createPool_revert_maxFeeExceeded() public {
        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 1000,
                maxFeeAmount: 1001,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 1002,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(
            details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(AMMStandardHook__PoolFeeTooHigh.selector)
        );
    }

    function test_createPool_revert_pairTokenNotWL() public {
        uint256 listId = _executeCreatePairTokenWhitelist(address(this), "newWL", bytes4(0));
        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(currency3);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeUpdatePairTokenWhitelist(address(this), listId, pairTokens, true, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: uint56(listId),
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency2),
            token1: address(currency4),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(
            details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(AMMStandardHook__PairNotAllowed.selector)
        );
    }

    function test_createPool_revert_callerNotWL() public {
        uint256 listId = _executeCreateLpWhitelist(address(this), "newWL", bytes4(0));
        address[] memory lp = new address[](1);
        lp[0] = address(currency3);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeUpdateLpWhitelist(address(this), listId, lp, true, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: uint56(listId)
            }),
            hooksToSync,
            bytes4(0)
        );

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        _createDynamicPoolNoHookData(
            details,
            10,
            1_120_455_419_495_722_798_374_638_764_549_163,
            bytes4(AMMStandardHook__LiquidityProviderNotAllowed.selector)
        );
    }

    function test_addLiquidity_providerWL() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        uint256 listId = _executeCreateLpWhitelist(address(this), "newWL", bytes4(0));
        address[] memory lp = new address[](1);
        lp[0] = address(alice);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeUpdateLpWhitelist(address(this), listId, lp, true, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: uint56(listId)
            }),
            hooksToSync,
            bytes4(0)
        );

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));
    }

    function test_addLiquidity_revert_providerNotWL() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        uint256 listId = _executeCreateLpWhitelist(address(this), "newWL", bytes4(0));
        address[] memory lp = new address[](1);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeUpdateLpWhitelist(address(this), listId, lp, true, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: uint56(listId)
            }),
            hooksToSync,
            bytes4(0)
        );

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(
            dynamicParams, liquidityParams, alice, bytes4(AMMStandardHook__LiquidityProviderNotAllowed.selector)
        );
    }

    function test_singleSwap_withTokenHook_revert_tradingIsPaused() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: true,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1000e6,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency2),
            tokenOut: address(currency3)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(AMMStandardHook__TradingPaused.selector)
        );
    }

    function test_singleSwap_withTokenHook_revert_lowerPriceBound() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(currency3);
        uint160[] memory lowerBound = new uint160[](1);
        uint160[] memory upperBound = new uint160[](1);

        lowerBound[0] = dynamicPool.getCurrentPriceX96(address(amm), poolId) + 1;

        _executeSetPricingBounds(
            currency2Owner, address(currency2), pairTokens, lowerBound, upperBound, hooksToSync, bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 10,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );
    }

    function test_singleSwap_withTokenHook_revert_upperPriceBound() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(currency3);
        uint160[] memory lowerBound = new uint160[](1);
        uint160[] memory upperBound = new uint160[](1);

        upperBound[0] = dynamicPool.getCurrentPriceX96(address(amm), poolId) - 1;

        _executeSetPricingBounds(
            currency2Owner, address(currency2), pairTokens, lowerBound, upperBound, hooksToSync, bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency2),
            tokenOut: address(currency3)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );
    }

    function test_singleSwap_withTokenHook_tokenFeeSell() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency3Owner,
            address(currency3),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 100,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_tokenFeeBuy() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 100,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_pairedFeeBuy() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 100,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_pairedFeeSell() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory tokenSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 100,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), tokenSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), tokenSettings, hooksToSync, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_pairedFeeSell_partialFill() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory tokenSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 100,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), tokenSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), tokenSettings, hooksToSync, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 10 ether,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        uint160 priceLimit = dynamicPool.getCurrentPriceX96(address(amm), poolId) * 9999 / 10_000;
        SwapHooksExtraData memory swapHooksExtraData;
        swapHooksExtraData.poolType = abi.encode(priceLimit);

        changePrank(swapOrder.recipient);
        (uint256 amountIn,) = _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            swapHooksExtraData,
            bytes(""),
            bytes4(0)
        );
        assertLt(amountIn, uint256(swapOrder.amountSpecified), "Full Amount In Used");
    }

    function test_singleSwap_withTokenHook_tokenFeeSell_hopFee() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency3Owner,
            address(currency3),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 100,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_tokenFeeBuy_hopFee() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 100,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_pairedFeeBuy_hopFee() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 0,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 100,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_pairedFeeSell_hopFee() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory tokenSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 100,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), tokenSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), tokenSettings, hooksToSync, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: 1_000_000,
            minAmountSpecified: 0,
            limitAmount: 0,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_swapByOutput_tokenFeeSell_hopFee() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory hookSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 100,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 0,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), hookSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), hookSettings, hooksToSync, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_swapByOutput_tokenFeeSell_hopFee_partialFill() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory hookSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 100,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 0,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), hookSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), hookSettings, hooksToSync, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -100 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        uint160 priceLimit = dynamicPool.getCurrentPriceX96(address(amm), poolId) * 9999 / 10_000;
        SwapHooksExtraData memory swapHooksExtraData;
        swapHooksExtraData.poolType = abi.encode(priceLimit);

        changePrank(swapOrder.recipient);
        (, uint256 amountOut) = _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            swapHooksExtraData,
            bytes(""),
            bytes4(0)
        );
        assertLt(amountOut, uint256(-swapOrder.amountSpecified), "Full Amount Out Used");
    }

    function test_singleSwap_withTokenHook_swapByOutput_tokenFeeBuy_hopFee() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 100,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_swapByOutput_tokenFeeBuy_hopFee_partialFill() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 100,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -30 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        uint160 priceLimit = dynamicPool.getCurrentPriceX96(address(amm), poolId) * 9999 / 10_000;
        SwapHooksExtraData memory swapHooksExtraData;
        swapHooksExtraData.poolType = abi.encode(priceLimit);

        changePrank(swapOrder.recipient);
        (,uint256 amountOut) = _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            swapHooksExtraData,
            bytes(""),
            bytes4(0)
        );
        assertLt(amountOut, uint256(-swapOrder.amountSpecified), "Full Amount Out Used");
    }

    function test_singleSwap_withTokenHook_swapByOutput_pairedFeeBuy_hopFee() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory tokenSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 100,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), tokenSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), tokenSettings, hooksToSync, bytes4(0));

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_swapByOutput_pairedFeeSell_hopFee() public {
        address[] memory hopTokens = new address[](2);
        hopTokens[0] = address(currency3);
        hopTokens[1] = address(currency2);
        uint16[] memory hopFees = new uint16[](2);
        hopFees[0] = 100;
        hopFees[1] = 100;
        changePrank(AMM_ADMIN);
        _setTokenFees(hopTokens, hopFees, bytes4(0));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory tokenSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 100,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), tokenSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), tokenSettings, hooksToSync, bytes4(0));

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_swapByOutput_tokenFeeBuy() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettingsNoExtensions(
            currency2Owner,
            address(currency2),
            HookTokenSettings({
                initialized: true,
                tradingIsPaused: false,
                blockDirectSwaps: false,
                checkDisabledPools: false,
                tokenFeeBuyBPS: 100,
                tokenFeeSellBPS: 0,
                pairedFeeBuyBPS: 0,
                pairedFeeSellBPS: 0,
                minFeeAmount: 0,
                maxFeeAmount: 10_000,
                poolTypeWhitelistId: 0,
                pairedTokenWhitelistId: 0,
                lpWhitelistId: 0
            }),
            hooksToSync,
            bytes4(0)
        );

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_swapByOutput_tokenFeeSell() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory hookSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 100,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 0,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), hookSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), hookSettings, hooksToSync, bytes4(0));

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_swapByOutput_pairedFeeBuy() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory hookSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 100,
            pairedFeeSellBPS: 0,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), hookSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), hookSettings, hooksToSync, bytes4(0));

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_withTokenHook_swapByOutput_pairedFeeSell() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory hookSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 100,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), hookSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), hookSettings, hooksToSync, bytes4(0));

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_collectHookFees() public {
        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(dynamicPool),
            fee: 500,
            token0: address(currency3),
            token1: address(currency2),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes32 poolId =
            _createDynamicPoolNoHookData(details, 10, 1_120_455_419_495_722_798_374_638_764_549_163, bytes4(0));

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 0,
            minLiquidityAmount1: 0,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        DynamicLiquidityModificationParams memory dynamicParams = DynamicLiquidityModificationParams({
            tickLower: -887_270,
            tickUpper: 887_270,
            liquidityChange: 18_052_084_844_744_799_965,
            snapSqrtPriceX96: 0
        });

        _mintAndApprove(address(currency2), alice, address(amm), 1_000_000 ether);
        _mintAndApprove(address(currency3), alice, address(amm), 1_000_000 ether);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory hookSettings = HookTokenSettings({
            initialized: true,
            tradingIsPaused: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 100,
            minFeeAmount: 0,
            maxFeeAmount: 10_000,
            poolTypeWhitelistId: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0
        });

        _executeSetTokenSettingsNoExtensions(currency2Owner, address(currency2), hookSettings, hooksToSync, bytes4(0));

        _executeSetTokenSettingsNoExtensions(currency3Owner, address(currency3), hookSettings, hooksToSync, bytes4(0));

        _addDynamicLiquidityNoHookData(dynamicParams, liquidityParams, alice, bytes4(0));

        SwapOrder memory swapOrder = SwapOrder({
            deadline: block.timestamp + 1000,
            recipient: alice,
            amountSpecified: -1 ether,
            minAmountSpecified: 0,
            limitAmount: type(uint256).max,
            tokenIn: address(currency3),
            tokenOut: address(currency2)
        });

        changePrank(swapOrder.recipient);
        _executeDynamicPoolSingleSwap(
            swapOrder,
            poolId,
            BPSFeeWithRecipient({BPS: 0, recipient: address(0)}),
            FlatFeeWithRecipient({amount: 0, recipient: address(0)}),
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );

        {
            address[] memory tokensToCollect = new address[](2);
            tokensToCollect[0] = address(currency2);
            tokensToCollect[1] = address(currency3);

            for (uint256 i = 0; i < tokensToCollect.length; i++) {
                for (uint256 j = 0; j < tokensToCollect.length; j++) {
                    uint256 tokensOwed = amm.getHookFeesOwedByToken(tokensToCollect[i], tokensToCollect[j]);
                    _collectHookFeesByToken(
                        ERC20Mock(tokensToCollect[i]).owner(),
                        tokensToCollect[i],
                        tokensToCollect[j],
                        ERC20Mock(tokensToCollect[i]).owner(),
                        tokensOwed,
                        bytes4(0)
                    );
                }
            }
        }
    }

    function test_multiSwap_withTokenHook_tokenFeeBuy() public {}
    function test_multiSwap_withTokenHook_tokenFeeSell() public {}
    function test_multiSwap_withTokenHook_pairedFeeBuy() public {}
    function test_multiSwap_withTokenHook_pairedFeeSell() public {}

    function _calculateHookFeeBeforeSwapSwapByInput(uint256 amountSpecified, SwapOrder memory swapOrder, address token)
        internal
        view
        override
        returns (uint256 hookFee)
    {
        HookTokenSettings memory hookSettings = creatorHookSettingsRegistry.getTokenSettings(token);
        if (token == swapOrder.tokenIn) {
            hookFee = FullMath.mulDiv(amountSpecified, hookSettings.tokenFeeSellBPS, MAX_BPS);
        } else if (token == swapOrder.tokenOut) {
            hookFee = FullMath.mulDiv(amountSpecified, hookSettings.pairedFeeBuyBPS, MAX_BPS);
        }
    }

    function _calculateHookFeeAfterSwapSwapByInput(uint256 amountUnspecified, SwapOrder memory swapOrder, address token)
        internal
        view
        override
        returns (uint256 hookFee)
    {
        HookTokenSettings memory hookSettings = creatorHookSettingsRegistry.getTokenSettings(token);
        if (token == swapOrder.tokenIn) {
            hookFee = FullMath.mulDiv(amountUnspecified, hookSettings.pairedFeeSellBPS, MAX_BPS);
        } else if (token == swapOrder.tokenOut) {
            hookFee = FullMath.mulDiv(amountUnspecified, hookSettings.tokenFeeBuyBPS, MAX_BPS);
        }
    }

    function _calculateHookFeeBeforeSwapSwapByOutput(uint256 amountSpecified, SwapOrder memory swapOrder, address token)
        internal
        view
        override
        returns (uint256 hookFee)
    {
        HookTokenSettings memory hookSettings = creatorHookSettingsRegistry.getTokenSettings(token);
        if (token == swapOrder.tokenIn) {
            hookFee = FullMath.mulDiv(amountSpecified, hookSettings.pairedFeeSellBPS, MAX_BPS);
        } else if (token == swapOrder.tokenOut) {
            hookFee = FullMath.mulDiv(amountSpecified, hookSettings.tokenFeeBuyBPS, MAX_BPS);
        }
    }

    function _calculateHookFeeAfterSwapSwapByOutput(uint256 amountUnspecified, SwapOrder memory swapOrder, address token)
        internal
        view
        override
        returns (uint256 hookFee)
    {
        HookTokenSettings memory hookSettings = creatorHookSettingsRegistry.getTokenSettings(token);
        if (token == swapOrder.tokenIn) {
            hookFee = FullMath.mulDiv(amountUnspecified, hookSettings.tokenFeeSellBPS, MAX_BPS);
        } else if (token == swapOrder.tokenOut) {
            hookFee = FullMath.mulDiv(amountUnspecified, hookSettings.pairedFeeBuyBPS, MAX_BPS);
        }
    }
}
