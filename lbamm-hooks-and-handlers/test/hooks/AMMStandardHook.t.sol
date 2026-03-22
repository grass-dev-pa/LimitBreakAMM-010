pragma solidity ^0.8.24;

import "../HooksAndHandlersBase.t.sol";
import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";

contract AMMStandardHookTest is HooksAndHandlersBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_constructorInputSanitation() public {
        vm.expectRevert(AMMStandardHook__InvalidAddress.selector);
        new AMMStandardHook(address(1), address(0));

        vm.expectRevert(AMMStandardHook__InvalidAddress.selector);
        new AMMStandardHook(address(0), address(1));
    }

    function test_registryUpdateWhitelistPairToken() public {
        uint256 whitelistId = 1;
        address[] memory pairTokens = new address[](2);
        pairTokens[0] = address(0x111);
        pairTokens[1] = address(0x222);

        _executeRegistryUpdateWhitelistPairToken(
            address(creatorHookSettingsRegistry), whitelistId, pairTokens, true, bytes4(0)
        );

        _executeRegistryUpdateWhitelistPairToken(
            address(creatorHookSettingsRegistry), whitelistId, pairTokens, false, bytes4(0)
        );

        address unauthorizedCaller = address(0xBAD);
        _executeRegistryUpdateWhitelistPairToken(
            unauthorizedCaller, whitelistId, pairTokens, true, AMMStandardHook__CallerIsNotRegistry.selector
        );
    }

    function test_registryUpdateWhitelistLPAddress() public {
        uint256 whitelistId = 1;
        address[] memory lpAddress = new address[](2);
        lpAddress[0] = address(0x111);
        lpAddress[1] = address(0x222);

        _executeRegistryUpdateWhitelistLpAddress(
            address(creatorHookSettingsRegistry), whitelistId, lpAddress, true, bytes4(0)
        );

        _executeRegistryUpdateWhitelistLpAddress(
            address(creatorHookSettingsRegistry), whitelistId, lpAddress, false, bytes4(0)
        );

        address unauthorizedCaller = address(0xBAD);
        _executeRegistryUpdateWhitelistLpAddress(
            unauthorizedCaller, whitelistId, lpAddress, true, AMMStandardHook__CallerIsNotRegistry.selector
        );
    }

    function test_validateRemoveLiquidity_revert_HookFunctionNotSupported() public {
        vm.expectRevert(AMMStandardHook__HookFunctionNotSupported.selector);
        standardHook.validateRemoveLiquidity(
            false,
            LiquidityContext(address(0), address(0), address(0), bytes32("")),
            LiquidityModificationParams(address(0), bytes32(0), 0, 0, type(uint256).max, type(uint256).max, type(uint256).max, type(uint256).max, bytes("")),
            0,
            0,
            0,
            0,
            bytes("")
        );
    }

    function test_registryUpdateWhitelistPoolType() public {
        uint256 whitelistId = 1;
        address[] memory poolTypes = new address[](2);
        poolTypes[0] = address(0x111);
        poolTypes[1] = address(0x222);

        _executeRegistryUpdateWhitelistPoolType(
            address(creatorHookSettingsRegistry), whitelistId, poolTypes, true, bytes4(0)
        );

        _executeRegistryUpdateWhitelistPoolType(
            address(creatorHookSettingsRegistry), whitelistId, poolTypes, false, bytes4(0)
        );

        address unauthorizedCaller = address(0xBAD);
        _executeRegistryUpdateWhitelistPoolType(
            unauthorizedCaller, whitelistId, poolTypes, true, AMMStandardHook__CallerIsNotRegistry.selector
        );
    }

    function test_registryUpdateWhitelistLpAddress() public {
        uint256 whitelistId = 1;
        address[] memory lpAddresses = new address[](2);
        lpAddresses[0] = address(0x111);
        lpAddresses[1] = address(0x222);

        _executeRegistryUpdateWhitelistLpAddress(
            address(creatorHookSettingsRegistry), whitelistId, lpAddresses, true, bytes4(0)
        );

        _executeRegistryUpdateWhitelistLpAddress(
            address(creatorHookSettingsRegistry), whitelistId, lpAddresses, false, bytes4(0)
        );

        address unauthorizedCaller = address(0xBAD);
        _executeRegistryUpdateWhitelistLpAddress(
            unauthorizedCaller, whitelistId, lpAddresses, true, AMMStandardHook__CallerIsNotRegistry.selector
        );
    }

    function test_registryUpdateTokenSettings() public {
        HookTokenSettings memory settings = HookTokenSettings({
            initialized: true,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 10,
            tokenFeeSellBPS: 15,
            pairedFeeBuyBPS: 25,
            pairedFeeSellBPS: 30,
            poolTypeWhitelistId: 0,
            minFeeAmount: 1,
            maxFeeAmount: 1000,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0,
            tradingIsPaused: false
        });

        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(testToken), settings, bytes4(0)
        );

        address unauthorizedCaller = address(0xBAD);
        _executeRegistryUpdateTokenSettings(
            unauthorizedCaller, address(testToken), settings, AMMStandardHook__CallerIsNotRegistry.selector
        );
    }

    function test_registryUpdatePricingBounds() public {
        address[] memory pairTokens = new address[](3);
        pairTokens[0] = address(0x111);
        pairTokens[1] = address(0x222);
        pairTokens[2] = address(0x333);

        uint160[] memory minSqrtPriceX96 = new uint160[](3);
        minSqrtPriceX96[0] = 1_000;
        minSqrtPriceX96[1] = 2_000;
        minSqrtPriceX96[2] = 5_000;

        uint160[] memory maxSqrtPriceX96 = new uint160[](3);
        maxSqrtPriceX96[0] = 5_000;
        maxSqrtPriceX96[1] = 10_000;
        maxSqrtPriceX96[2] = 20_000;

        // set pricing bounds, 3 tokens
        _executeRegistryUpdatePricingBounds(
            address(creatorHookSettingsRegistry),
            address(testToken),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            bytes4(0)
        );

        // unset one token
        minSqrtPriceX96[0] = 1_001;
        minSqrtPriceX96[1] = 0;
        minSqrtPriceX96[2] = 5_001;
        maxSqrtPriceX96[0] = 5_001;
        maxSqrtPriceX96[1] = 0;
        maxSqrtPriceX96[2] = 20_001;
        _executeRegistryUpdatePricingBounds(
            address(creatorHookSettingsRegistry),
            address(testToken),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            bytes4(0)
        );

        uint160[] memory invalidMin = new uint160[](3);
        invalidMin[0] = 6_000;
        invalidMin[1] = 2_000;
        invalidMin[2] = 2_000;

        _executeRegistryUpdatePricingBounds(
            address(creatorHookSettingsRegistry),
            address(testToken),
            pairTokens,
            invalidMin,
            maxSqrtPriceX96,
            AMMStandardHook__MaxPriceMustBeGreaterThanOrEqualToMinPrice.selector
        );

        address unauthorizedCaller = address(0xBAD);
        _executeRegistryUpdatePricingBounds(
            unauthorizedCaller,
            address(testToken),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            AMMStandardHook__CallerIsNotRegistry.selector
        );
    }

    function test_registrySyncTokenSettings() public {
        // create extra lists to check log on list ids
        _executeCreatePairTokenWhitelist(bob, "", bytes4(0));
        _executeCreatePairTokenWhitelist(bob, "", bytes4(0));
        _executeCreateLpWhitelist(bob, "", bytes4(0));
        _executeCreateLpWhitelist(bob, "", bytes4(0));
        _executeCreateLpWhitelist(bob, "", bytes4(0));

        HookTokenSettings memory registrySettings = HookTokenSettings({
            initialized: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 50,
            tokenFeeSellBPS: 100,
            pairedFeeBuyBPS: 75,
            pairedFeeSellBPS: 150,
            poolTypeWhitelistId: 1,
            minFeeAmount: 10,
            maxFeeAmount: 2000,
            pairedTokenWhitelistId: 2,
            lpWhitelistId: 3,
            tradingIsPaused: false
        });

        bytes32[] memory emptyDataExtensions;
        bytes[] memory emptyDataSettings;
        bytes32[] memory emptyWordExtensions;
        bytes32[] memory emptyWordSettings;
        address[] memory emptyHooksToSync;

        _executeSetTokenSettings(
            testToken.owner(),
            address(testToken),
            registrySettings,
            emptyDataExtensions,
            emptyDataSettings,
            emptyWordExtensions,
            emptyWordSettings,
            emptyHooksToSync,
            bytes4(0)
        );

        _executeRegistrySyncTokenSettings(address(creatorHookSettingsRegistry), address(testToken), registrySettings, bytes4(0));

        address unauthorizedCaller = address(0xBAD);
        _executeRegistrySyncTokenSettings(
            unauthorizedCaller, address(testToken), registrySettings, AMMStandardHook__CallerIsNotRegistry.selector
        );
    }

    function test_beforeSwap() public {
        SwapContext memory context = SwapContext({
            executor: address(0x456),
            transferHandler: address(0),
            exchangeFeeRecipient: address(0),
            exchangeFeeBPS: 0,
            feeOnTopRecipient: address(0),
            feeOnTopAmount: 0,
            recipient: address(0x789),
            tokenIn: address(token0),
            tokenOut: address(token1),
            numberOfHops: 1
        });

        HookSwapParams memory swapParams = HookSwapParams({
            poolId: mockPool.getPoolId(),
            tokenIn: address(token0),
            tokenOut: address(token1),
            amount: 1000 ether,
            inputSwap: true,
            hookForInputToken: true,
            hopIndex: 0
        });

        bytes memory hookData = "";

        HookTokenSettings memory settings;
        settings.initialized = true;
        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), settings, bytes4(0)
        );

        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));

        HookTokenSettings memory pausedSettings = HookTokenSettings({
            initialized: true,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 0,
            tokenFeeSellBPS: 0,
            pairedFeeBuyBPS: 0,
            pairedFeeSellBPS: 0,
            poolTypeWhitelistId: 0,
            minFeeAmount: 0,
            maxFeeAmount: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0,
            tradingIsPaused: true
        });

        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), pausedSettings, bytes4(0)
        );

        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, AMMStandardHook__TradingPaused.selector);
    }

    function test_beforeSwap_hookNotSynced() public {
        SwapContext memory context = SwapContext({
            executor: address(0x456),
            transferHandler: address(0),
            exchangeFeeRecipient: address(0),
            exchangeFeeBPS: 0,
            feeOnTopRecipient: address(0),
            feeOnTopAmount: 0,
            recipient: address(0x789),
            tokenIn: address(token2),
            tokenOut: address(token1),
            numberOfHops: 1
        });

        HookSwapParams memory swapParams = HookSwapParams({
            poolId: mockPool.getPoolId(),
            tokenIn: address(token2),
            tokenOut: address(token1),
            amount: 1000 ether,
            inputSwap: true,
            hookForInputToken: true,
            hopIndex: 0
        });

        bytes memory hookData = "";

        HookTokenSettings memory settings = HookTokenSettings({
            initialized: true,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 10,
            tokenFeeSellBPS: 15,
            pairedFeeBuyBPS: 25,
            pairedFeeSellBPS: 30,
            poolTypeWhitelistId: 0,
            minFeeAmount: 0,
            maxFeeAmount: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0,
            tradingIsPaused: false
        });

        address[] memory hooksToSync = new address[](0);

        _executeSetTokenSettingsNoExtensions(token2.owner(), address(token2), settings, hooksToSync, bytes4(0));

        _executeBeforeSwap(address(amm), context, swapParams, hookData, 1_500_000_000_000_000_000, bytes4(0));
    }

    function test_validatePoolCreation() public {
        address creator = address(0x123);

        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(token0),
            token1: address(token1),
            fee: 3000,
            poolType: address(0x456),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes memory hookData = "";

        HookTokenSettings memory settings;
        settings.initialized = true;
        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), settings, bytes4(0)
        );

        _executeValidatePoolCreation(address(amm), creator, true, details, hookData, bytes4(0));

        HookTokenSettings memory restrictiveSettings = HookTokenSettings({
            initialized: true,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 10,
            tokenFeeSellBPS: 15,
            pairedFeeBuyBPS: 25,
            pairedFeeSellBPS: 30,
            poolTypeWhitelistId: 0,
            minFeeAmount: 5000,
            maxFeeAmount: 10_000,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0,
            tradingIsPaused: false
        });

        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), restrictiveSettings, bytes4(0)
        );

        _executeValidatePoolCreation(
            address(amm), creator, true, details, hookData, AMMStandardHook__PoolFeeTooLow.selector
        );
    }

    function test_validatePoolCreation_FeeTooHigh() public {
        address creator = address(0x123);

        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(token0),
            token1: address(token1),
            fee: 8500,
            poolType: address(0x456),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes memory hookData = "";

        HookTokenSettings memory settings;
        settings.initialized = true;
        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), settings, bytes4(0)
        );

        _executeValidatePoolCreation(address(amm), creator, true, details, hookData, bytes4(0));

        HookTokenSettings memory restrictiveSettings = HookTokenSettings({
            initialized: true,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 10,
            tokenFeeSellBPS: 15,
            pairedFeeBuyBPS: 25,
            pairedFeeSellBPS: 30,
            poolTypeWhitelistId: 0,
            minFeeAmount: 5000,
            maxFeeAmount: 7500,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0,
            tradingIsPaused: false
        });

        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), restrictiveSettings, bytes4(0)
        );

        _executeValidatePoolCreation(
            address(amm), creator, true, details, hookData, AMMStandardHook__PoolFeeTooHigh.selector
        );
    }

    function test_validatePoolCreation_DynamicFee() public {
        address creator = address(0x123);

        PoolCreationDetails memory details = PoolCreationDetails({
            token0: address(token0),
            token1: address(token1),
            fee: 55555,
            poolType: address(0x456),
            poolHook: address(0),
            poolParams: bytes("")
        });

        bytes memory hookData = "";

        HookTokenSettings memory settings;
        settings.initialized = true;
        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), settings, bytes4(0)
        );

        _executeValidatePoolCreation(address(amm), creator, true, details, hookData, bytes4(0));

        HookTokenSettings memory restrictiveSettings = HookTokenSettings({
            initialized: true,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 10,
            tokenFeeSellBPS: 15,
            pairedFeeBuyBPS: 25,
            pairedFeeSellBPS: 30,
            poolTypeWhitelistId: 0,
            minFeeAmount: 5000,
            maxFeeAmount: 55555,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0,
            tradingIsPaused: false
        });

        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), restrictiveSettings, bytes4(0)
        );

        _executeValidatePoolCreation(
            address(amm), creator, true, details, hookData, bytes4(0)
        );
    }

    function test_validateAddLiquidity() public {
        address provider = address(0x123);

        LiquidityContext memory context = LiquidityContext({
            token0: address(token0),
            token1: address(token1),
            provider: provider,
            positionId: bytes32("position123")
        });

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: bytes32("pool123"),
            minLiquidityAmount0: 1000 ether,
            minLiquidityAmount1: 1000 ether,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        bytes memory hookData = "";

        HookTokenSettings memory settings;
        settings.initialized = true;
        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), settings, bytes4(0)
        );

        _executeValidateAddLiquidity(
            address(amm), true, context, liquidityParams, 1000 ether, 1000 ether, 0, 0, hookData, bytes4(0)
        );

        HookTokenSettings memory restrictiveSettings = HookTokenSettings({
            initialized: true,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 10,
            tokenFeeSellBPS: 15,
            pairedFeeBuyBPS: 25,
            pairedFeeSellBPS: 30,
            poolTypeWhitelistId: 0,
            minFeeAmount: 0,
            maxFeeAmount: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 1,
            tradingIsPaused: false
        });

        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), restrictiveSettings, bytes4(0)
        );

        _executeValidateAddLiquidity(
            address(amm),
            true,
            context,
            liquidityParams,
            1000 ether,
            1000 ether,
            0,
            0,
            hookData,
            AMMStandardHook__LiquidityProviderNotAllowed.selector
        );
    }

    function test_validateAddLiquidity_RevertsWhenPoolDisabled() public {
        address provider = address(0x123);

        MockPoolTypeCreation ptc = new MockPoolTypeCreation();
        vm.etch(address(0x1111111111), address(ptc).code);

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(0x1111111111),
            fee: 0,
            token0: address(token0),
            token1: address(token1),
            poolHook: address(0),
            poolParams: bytes("")
        });
        (bytes32 poolId,,) = amm.createPool(details, bytes(""), bytes(""), bytes(""), bytes(""));

        LiquidityContext memory context = LiquidityContext({
            token0: address(token0),
            token1: address(token1),
            provider: provider,
            positionId: bytes32("position123")
        });

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 1000 ether,
            minLiquidityAmount1: 1000 ether,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        bytes memory hookData = "";

        HookTokenSettings memory settings;
        settings.initialized = true;
        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), settings, bytes4(0)
        );


        uint256 snapshotId = vm.snapshot();
        assertFalse(creatorHookSettingsRegistry.isPoolDisabled(liquidityParams.poolId));
        changePrank(token0.owner());
        creatorHookSettingsRegistry.setPoolDisabled(address(token0), liquidityParams.poolId, true);
        assertTrue(creatorHookSettingsRegistry.isPoolDisabled(liquidityParams.poolId));

        // Pool is allowed disabled until hook gets restrictive settings with disabled pool check enabled
        _executeValidateAddLiquidity(
            address(amm), true, context, liquidityParams, 1000 ether, 1000 ether, 0, 0, hookData, bytes4(0)
        );

        HookTokenSettings memory restrictiveSettings = HookTokenSettings({
            initialized: true,
            blockDirectSwaps: false,
            checkDisabledPools: true,
            tokenFeeBuyBPS: 10,
            tokenFeeSellBPS: 15,
            pairedFeeBuyBPS: 25,
            pairedFeeSellBPS: 30,
            poolTypeWhitelistId: 0,
            minFeeAmount: 0,
            maxFeeAmount: 0,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0,
            tradingIsPaused: false
        });

        {
            _executeRegistryUpdateTokenSettings(
                address(creatorHookSettingsRegistry), address(token0), restrictiveSettings, bytes4(0)
            );

            // Reverts with pool disabled
            _executeValidateAddLiquidity(
                address(amm),
                true,
                context,
                liquidityParams,
                1000 ether,
                1000 ether,
                0,
                0,
                hookData,
                AMMStandardHook__PoolDisabled.selector
            );
        }

        {
            vm.revertTo(snapshotId);

            assertFalse(creatorHookSettingsRegistry.isPoolDisabled(liquidityParams.poolId));
            changePrank(token1.owner());
            creatorHookSettingsRegistry.setPoolDisabled(address(token1), liquidityParams.poolId, true);
            assertTrue(creatorHookSettingsRegistry.isPoolDisabled(liquidityParams.poolId));

            // Pool is allowed disabled until hook gets restrictive settings with disabled pool check enabled
            _executeValidateAddLiquidity(
                address(amm), true, context, liquidityParams, 1000 ether, 1000 ether, 0, 0, hookData, bytes4(0)
            );

            _executeRegistryUpdateTokenSettings(
                address(creatorHookSettingsRegistry), address(token0), restrictiveSettings, bytes4(0)
            );

            // Reverts with pool disabled
            _executeValidateAddLiquidity(
                address(amm),
                true,
                context,
                liquidityParams,
                1000 ether,
                1000 ether,
                0,
                0,
                hookData,
                AMMStandardHook__PoolDisabled.selector
            );
        }

        {
            vm.revertTo(snapshotId);

            assertFalse(creatorHookSettingsRegistry.isPoolDisabled(liquidityParams.poolId));
            changePrank(token0.owner());
            creatorHookSettingsRegistry.setPoolDisabled(address(token0), liquidityParams.poolId, true);
            changePrank(token1.owner());
            creatorHookSettingsRegistry.setPoolDisabled(address(token1), liquidityParams.poolId, true);
            changePrank(token2.owner());
            vm.expectRevert(CreatorHookSettingsRegistry__TokenIsNotInPair.selector);
            creatorHookSettingsRegistry.setPoolDisabled(address(token2), liquidityParams.poolId, true);
            assertTrue(creatorHookSettingsRegistry.isPoolDisabled(liquidityParams.poolId));
            
            // Pool is allowed disabled until hook gets restrictive settings with disabled pool check enabled
            _executeValidateAddLiquidity(
                address(amm), true, context, liquidityParams, 1000 ether, 1000 ether, 0, 0, hookData, bytes4(0)
            );

            _executeRegistryUpdateTokenSettings(
                address(creatorHookSettingsRegistry), address(token0), restrictiveSettings, bytes4(0)
            );

            // Reverts with pool disabled
            _executeValidateAddLiquidity(
                address(amm),
                true,
                context,
                liquidityParams,
                1000 ether,
                1000 ether,
                0,
                0,
                hookData,
                AMMStandardHook__PoolDisabled.selector
            );
        }
    }

    function test_validateAddLiquidity_RevertsWhenPriceMovesOutOfRange() public {

        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(token1);

        uint160[] memory minSqrtPriceX96 = new uint160[](1);
        minSqrtPriceX96[0] = 1_000;

        uint160[] memory maxSqrtPriceX96 = new uint160[](1);
        maxSqrtPriceX96[0] = 5_000;

        // set pricing bounds, 3 tokens
        _executeRegistryUpdatePricingBounds(
            address(creatorHookSettingsRegistry),
            address(token0),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            bytes4(0)
        );

        address provider = address(0x123);

        MockPoolTypeCreation ptc = new MockPoolTypeCreation();
        vm.etch(address(0x1111111111), address(ptc).code);
        ptc = MockPoolTypeCreation(address(0x1111111111));

        PoolCreationDetails memory details = PoolCreationDetails({
            poolType: address(ptc),
            fee: 0,
            token0: address(token0),
            token1: address(token1),
            poolHook: address(0),
            poolParams: bytes("")
        });
        (bytes32 poolId,,) = amm.createPool(details, bytes(""), bytes(""), bytes(""), bytes(""));

        LiquidityContext memory context = LiquidityContext({
            token0: address(token0),
            token1: address(token1),
            provider: provider,
            positionId: bytes32("position123")
        });

        LiquidityModificationParams memory liquidityParams = LiquidityModificationParams({
            liquidityHook: address(0),
            poolId: poolId,
            minLiquidityAmount0: 1000 ether,
            minLiquidityAmount1: 1000 ether,
            maxLiquidityAmount0: type(uint256).max,
            maxLiquidityAmount1: type(uint256).max,
            maxHookFee0: type(uint256).max,
            maxHookFee1: type(uint256).max,
            poolParams: bytes("")
        });

        bytes memory hookData = "";

        HookTokenSettings memory settings;
        settings.initialized = true;
        _executeRegistryUpdateTokenSettings(
            address(creatorHookSettingsRegistry), address(token0), settings, bytes4(0)
        );

        uint256 snapshotId = vm.snapshot();

        // Add liquidity validation passes
        ptc.setCurrentPriceX96(2_500);
        _executeValidateAddLiquidity(
            address(amm), true, context, liquidityParams, 1000 ether, 1000 ether, 0, 0, hookData, bytes4(0)
        );

        // Add liquidity validation fails with invalid price (low)
        ptc.setCurrentPriceX96(999);
        _executeValidateAddLiquidity(
            address(amm), true, context, liquidityParams, 1000 ether, 1000 ether, 0, 0, hookData, AMMStandardHook__InvalidPrice.selector
        );

        // Add liquidity validation fails with invalid price (high)
        ptc.setCurrentPriceX96(5_001);
        _executeValidateAddLiquidity(
            address(amm), true, context, liquidityParams, 1000 ether, 1000 ether, 0, 0, hookData, AMMStandardHook__InvalidPrice.selector
        );
    }

    function test_afterSwap_lowerPriceBound() public {
        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(token1);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        uint160[] memory lowerBounds = new uint160[](1);
        uint160[] memory upperBounds = new uint160[](1);

        lowerBounds[0] = uint160(mockPool.getCurrentPriceX96(address(0), bytes32("pool123")) + 1);

        upperBounds[0] = 0;

        HookTokenSettings memory settings;
        _executeSetTokenSettings(
            token0.owner(),
            address(token0),
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            bytes4(0) // No error expected
        );
        _executeSetTokenSettings(
            token1.owner(),
            address(token1),
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            bytes4(0) // No error expected
        );
        _executeSetPricingBounds(
            token0.owner(), address(token0), pairTokens, lowerBounds, upperBounds, hooksToSync, bytes4(0)
        );

        SwapContext memory context = SwapContext({
            executor: address(0x456),
            transferHandler: address(0),
            exchangeFeeRecipient: address(0),
            exchangeFeeBPS: 0,
            feeOnTopRecipient: address(0),
            feeOnTopAmount: 0,
            recipient: address(0x789),
            tokenIn: address(token0),
            tokenOut: address(token1),
            numberOfHops: 1
        });

        HookSwapParams memory swapParams = HookSwapParams({
            poolId: mockPool.getPoolId(),
            tokenIn: address(token0),
            tokenOut: address(token1),
            amount: 1000 ether,
            inputSwap: true,
            hookForInputToken: true,
            hopIndex: 0
        });

        bytes memory hookData = "";

        uint256 expectedOutputFee = 0;

        // revert because we are below the price bound and moving lower
        _executeAfterSwap(
            address(amm), context, swapParams, hookData, expectedOutputFee, bytes4(AMMStandardHook__InvalidPrice.selector)
        );
        swapParams.tokenIn = address(token1);
        swapParams.tokenOut = address(token0);
        // no revert because we are below the price bound but moving higher
        _executeAfterSwap(address(amm), context, swapParams, hookData, expectedOutputFee, bytes4(0));
    }

    function test_afterSwap_upperPriceBound() public {
        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(token1);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        uint160[] memory lowerBounds = new uint160[](1);
        uint160[] memory upperBounds = new uint160[](1);

        upperBounds[0] = uint160(mockPool.getCurrentPriceX96(address(0), bytes32("pool123")) - 1);

        lowerBounds[0] = 0;

        _executeSetPricingBounds(
            token0.owner(), address(token0), pairTokens, lowerBounds, upperBounds, hooksToSync, bytes4(0)
        );
        pairTokens[0] = address(token0);
        _executeSetPricingBounds(
            token1.owner(), address(token1), pairTokens, lowerBounds, upperBounds, hooksToSync, bytes4(0)
        );

        HookTokenSettings memory settings;
        _executeSetTokenSettings(
            token0.owner(),
            address(token0),
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            bytes4(0) // No error expected
        );
        _executeSetTokenSettings(
            token1.owner(),
            address(token1),
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            bytes4(0) // No error expected
        );

        SwapContext memory context = SwapContext({
            executor: address(0x456),
            transferHandler: address(0),
            recipient: address(0x789),
            exchangeFeeRecipient: address(0),
            exchangeFeeBPS: 0,
            feeOnTopRecipient: address(0),
            feeOnTopAmount: 0,
            tokenIn: address(token0),
            tokenOut: address(token1),
            numberOfHops: 1
        });

        HookSwapParams memory swapParams = HookSwapParams({
            poolId: mockPool.getPoolId(),
            tokenIn: address(token0),
            tokenOut: address(token1),
            amount: 1000 ether,
            inputSwap: true,
            hookForInputToken: true,
            hopIndex: 0
        });

        bytes memory hookData = "";

        uint256 expectedOutputFee = 0;

        // no revert because we are above the price bound but moving lower
        _executeAfterSwap(address(amm), context, swapParams, hookData, expectedOutputFee, bytes4(0));
        swapParams.tokenIn = address(token1);
        swapParams.tokenOut = address(token0);
        // revert because we are above the price bound and moving higher
        _executeAfterSwap(
            address(amm), context, swapParams, hookData, expectedOutputFee, bytes4(AMMStandardHook__InvalidPrice.selector)
        );
    }



    function test_directSwap_Blocked() public {
        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        HookTokenSettings memory settings;
        settings.blockDirectSwaps = true;
        _executeSetTokenSettings(
            token0.owner(),
            address(token0),
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            bytes4(0) // No error expected
        );
        _executeSetTokenSettings(
            token1.owner(),
            address(token1),
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            bytes4(0) // No error expected
        );

        SwapContext memory context = SwapContext({
            executor: address(0x456),
            transferHandler: address(0),
            recipient: address(0x789),
            exchangeFeeRecipient: address(0),
            exchangeFeeBPS: 0,
            feeOnTopRecipient: address(0),
            feeOnTopAmount: 0,
            tokenIn: address(token0),
            tokenOut: address(token1),
            numberOfHops: 1
        });

        HookSwapParams memory swapParams = HookSwapParams({
            poolId: bytes32(0),
            tokenIn: address(token0),
            tokenOut: address(token1),
            amount: 1000 ether,
            inputSwap: true,
            hookForInputToken: true,
            hopIndex: 0
        });

        bytes memory hookData = "";

        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__DirectSwapsNotAllowed.selector));
    }

    function test_directSwap_priceBounds() public {
        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(token1);

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        uint160[] memory lowerBounds = new uint160[](1);
        uint160[] memory upperBounds = new uint160[](1);

        lowerBounds[0] = SqrtPriceCalculator.computeRatioX96(1, 1000);
        upperBounds[0] = SqrtPriceCalculator.computeRatioX96(10, 1000);

        _executeSetPricingBounds(
            token0.owner(), address(token0), pairTokens, lowerBounds, upperBounds, hooksToSync, bytes4(0)
        );
        pairTokens[0] = address(token0);
        _executeSetPricingBounds(
            token1.owner(), address(token1), pairTokens, lowerBounds, upperBounds, hooksToSync, bytes4(0)
        );


        uint256 listId = _executeCreatePairTokenWhitelist(address(this), "MyPairedTokens", bytes4(0));
        pairTokens = new address[](2);
        pairTokens[0] = address(token0);
        pairTokens[1] = address(token1);
        _executeUpdatePairTokenWhitelist(address(this), listId, pairTokens, true, hooksToSync, bytes4(0));

        HookTokenSettings memory settings;
        settings.pairedTokenWhitelistId = uint56(listId);
        _executeSetTokenSettings(
            token0.owner(),
            address(token0),
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            bytes4(0) // No error expected
        );
        _executeSetTokenSettings(
            token1.owner(),
            address(token1),
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            bytes4(0) // No error expected
        );

        SwapContext memory context = SwapContext({
            executor: address(0x456),
            transferHandler: address(0),
            recipient: address(0x789),
            exchangeFeeRecipient: address(0),
            exchangeFeeBPS: 0,
            feeOnTopRecipient: address(0),
            feeOnTopAmount: 0,
            tokenIn: address(token0),
            tokenOut: address(token1),
            numberOfHops: 1
        });

        HookSwapParams memory swapParams = HookSwapParams({
            poolId: bytes32(0),
            tokenIn: address(token0),
            tokenOut: address(token1),
            amount: 1000 ether,
            inputSwap: true,
            hookForInputToken: true,
            hopIndex: 0
        });

        bytes memory hookData = "";

        // Swap 0->1, inputSwap
        // Simulate direct swap within bounds
        swapParams.amount = 1000 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 2 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));

        // Expect revert due to lower bound
        swapParams.amount = 1000 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 0.5 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__InvalidPrice.selector));

        // Expect revert due to lower bound
        swapParams.amount = 1000 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 11 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__InvalidPrice.selector));

        // Swap 1->0, inputSwap
        swapParams.tokenIn = address(token1);
        swapParams.tokenOut = address(token0);
        // Simulate direct swap within bounds
        swapParams.amount = 2 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 1000 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));

        // Expect revert due to lower bound
        swapParams.amount = 0.5 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 1000 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__InvalidPrice.selector));

        // Expect revert due to lower bound
        swapParams.amount = 11 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 1000 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__InvalidPrice.selector));

        // Swap 0->1, output swap
        swapParams.inputSwap = false;
        swapParams.tokenIn = address(token0);
        swapParams.tokenOut = address(token1);
        // Simulate direct swap within bounds
        swapParams.amount = 2 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 1000 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));

        // Expect revert due to lower bound
        swapParams.amount = 0.5 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 1000 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__InvalidPrice.selector));

        // Expect revert due to lower bound
        swapParams.amount = 11 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 1000 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__InvalidPrice.selector));

        // Swap 1->0, output swap
        swapParams.tokenIn = address(token1);
        swapParams.tokenOut = address(token0);
        // Simulate direct swap within bounds
        swapParams.amount = 1000 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 2 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));

        // Expect revert due to lower bound
        swapParams.amount = 1000 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 0.5 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__InvalidPrice.selector));

        // Expect revert due to lower bound
        swapParams.amount = 1000 ether;
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(0));
        swapParams.amount = 11 ether;
        _executeAfterSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__InvalidPrice.selector));


        // Expect revert due to invalid paired token
        swapParams.inputSwap = true;
        swapParams.tokenIn = address(token0);
        swapParams.tokenOut = address(token2);
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__PairNotAllowed.selector));

        // Expect revert due to invalid paired token
        swapParams.inputSwap = false;
        swapParams.hookForInputToken = false;
        swapParams.tokenIn = address(token2);
        swapParams.tokenOut = address(token1);
        _executeBeforeSwap(address(amm), context, swapParams, hookData, 0, bytes4(AMMStandardHook__PairNotAllowed.selector));
    }

    function test_validateCollectFees_revert_NotSupported() public {
        vm.expectRevert(AMMStandardHook__HookFunctionNotSupported.selector);
        standardHook.validateCollectFees(
            false,
            LiquidityContext(address(0), address(0), address(0), bytes32("")),
            LiquidityCollectFeesParams(address(0), bytes32(""), type(uint256).max, type(uint256).max, bytes("")),
            0,
            0,
            bytes("")
        );
    }

    function test_validateFlashloanFee_revert_NotSupported() public {
        vm.expectRevert(AMMStandardHook__TokenNotAllowedAsFlashloanFee.selector);
        standardHook.validateFlashloanFee(address(0), address(0), 0, address(0), 0, address(0), bytes(""));
    }

    function test_beforeFlashloan_revert_NotSupported() public {
        vm.expectRevert(AMMStandardHook__TokenNotAllowedAsFlashloan.selector);
        standardHook.beforeFlashloan(address(0), address(0), 0, address(0), bytes(""));
    }

    function test_setAndClearTokenHook() public {
        TokenFlagSettings memory tokenFlagSettings;
        tokenFlagSettings.beforeSwapHook = true;

        vm.startPrank(testToken.owner());
        _setTokenSettings(
            address(testToken),
            address(standardHook),
            tokenFlagSettings,
            bytes4(0)
        );

        _setTokenSettings(
            address(testToken),
            address(0),
            tokenFlagSettings,
            bytes4(LBAMM__UnsupportedHookFlags.selector)
        );

        tokenFlagSettings.beforeSwapHook = false;
        _setTokenSettings(
            address(testToken),
            address(0),
            tokenFlagSettings,
            bytes4(0)
        );
    }
}

contract MockPoolTypeCreation {
    uint160 currentPriceX96 = 999_999_999_999_999_999_999;

    function setCurrentPriceX96(uint160 currentPriceX96_) external {
        currentPriceX96 = currentPriceX96_;
    }

    function getCurrentPriceX96(address, bytes32) external view returns (uint160) {
        return currentPriceX96;
    }

    function getPoolId() public view returns (bytes32) {
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

    function createPool(
        PoolCreationDetails calldata
    ) external returns (bytes32 poolId) {
        poolId = getPoolId();
    }
}