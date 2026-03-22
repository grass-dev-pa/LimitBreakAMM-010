pragma solidity ^0.8.24;

import "@limitbreak/lb-amm-core/test/LBAMMCorePoolBase.t.sol";
import "@limitbreak/lb-amm-core/test/mocks/MockPool.sol";
import "../src/hooks/interfaces/IAMMStandardHook.sol";
import "../src/hooks/interfaces/ICreatorHookSettingsRegistry.sol";

import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";
import "../src/hooks/AMMStandardHook.sol";
import "../src/hooks/CreatorHookSettingsRegistry.sol";
import "./mocks/MockFeeHook.sol";

contract HooksAndHandlersBaseTest is LBAMMCorePoolBaseTest {
    CreatorHookSettingsRegistry public creatorHookSettingsRegistry;
    AMMStandardHook public standardHook;

    MockHookWithFees public feeHook;
    
    ERC20Mock internal testToken;
    MockPool internal mockPool;

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    ERC20Mock internal token2;

    function setUp() public virtual override {
        super.setUp();

        // Setup Hook Settings Registry and Standard Hook
        creatorHookSettingsRegistry = new CreatorHookSettingsRegistry(address(amm), AMM_ADMIN);
        standardHook = new AMMStandardHook(address(amm), address(creatorHookSettingsRegistry));

        feeHook = new MockHookWithFees();

        // Deploy Mock pool
        mockPool = new MockPool();
        address mockPoolAddress = address(111);
        vm.etch(mockPoolAddress, address(mockPool).code);
        mockPool = MockPool(mockPoolAddress);
        vm.label(mockPoolAddress, "MockPool");

        // Deploy test tokens
        token0 = new ERC20Mock("Token0", "TK0", 18);
        token1 = new ERC20Mock("Token1", "TK1", 18);
        token2 = new ERC20Mock("Token2", "TK2", 18);
        testToken = new ERC20Mock("test", "TEST", 18);

        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
    }

    //
    // Helper Functions - Creator Hook Settings Registry
    //

    function _executeCreatePairTokenWhitelist(address caller, string memory whitelistName, bytes4 errorSelector)
        internal
        returns (uint256 listId)
    {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(false, true, false, true);
            emit ICreatorHookSettingsRegistry.PairTokenWhitelistCreated(0, caller, whitelistName);
        }

        listId = creatorHookSettingsRegistry.createPairTokenWhitelist(whitelistName);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getPairTokenWhitelistOwner(listId), caller);
            assertEq(creatorHookSettingsRegistry.getPairTokensInList(listId).length, 0);
        }

        vm.stopPrank();
    }

    function _executeCreateLpWhitelist(address caller, string memory whitelistName, bytes4 errorSelector)
        internal
        returns (uint256 listId)
    {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(false, true, false, true);
            emit ICreatorHookSettingsRegistry.LpWhitelistCreated(0, caller, whitelistName);
        }

        listId = creatorHookSettingsRegistry.createLpWhitelist(whitelistName);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getLpWhitelistOwner(listId), caller);
            assertEq(creatorHookSettingsRegistry.getLpsInList(listId).length, 0);
        }

        vm.stopPrank();
    }

    function _executeCreatePoolTypeWhitelist(address caller, string memory whitelistName, bytes4 errorSelector)
        internal
        returns (uint256 listId)
    {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(false, true, false, true);
            emit ICreatorHookSettingsRegistry.PoolTypeWhitelistCreated(0, caller, whitelistName);
        }

        listId = creatorHookSettingsRegistry.createPoolTypeWhitelist(whitelistName);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getPoolTypeWhitelistOwner(listId), caller);
            // Assuming no pool types are added initially
            assertEq(creatorHookSettingsRegistry.getPoolTypesInList(listId).length, 0);
        }

        vm.stopPrank();
    }

    // Handler for transferPairTokenWhitelistOwnership
    function _executeTransferPairTokenWhitelistOwnership(
        address caller,
        uint256 listId,
        address newOwner,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        address currentOwner = creatorHookSettingsRegistry.getPairTokenWhitelistOwner(listId);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, false);
            emit ICreatorHookSettingsRegistry.PairTokenWhitelistOwnershipTransferred(listId, currentOwner, newOwner);
        }

        creatorHookSettingsRegistry.transferPairTokenWhitelistOwnership(listId, newOwner);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getPairTokenWhitelistOwner(listId), newOwner);
        }

        vm.stopPrank();
    }

    // Handler for transferLpWhitelistOwnership
    function _executeTransferLpWhitelistOwnership(
        address caller,
        uint256 listId,
        address newOwner,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        address currentOwner = creatorHookSettingsRegistry.getLpWhitelistOwner(listId);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, false);
            emit ICreatorHookSettingsRegistry.LpWhitelistOwnershipTransferred(listId, currentOwner, newOwner);
        }

        creatorHookSettingsRegistry.transferLpWhitelistOwnership(listId, newOwner);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getLpWhitelistOwner(listId), newOwner);
        }

        vm.stopPrank();
    }

    // Handler for transferPoolTypeWhitelistOwnership
    function _executeTransferPoolTypeWhitelistOwnership(
        address caller,
        uint256 listId,
        address newOwner,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            address currentOwner = creatorHookSettingsRegistry.getPoolTypeWhitelistOwner(listId);
            vm.expectEmit(true, true, true, false);
            emit ICreatorHookSettingsRegistry.PoolTypeWhitelistOwnershipTransferred(listId, currentOwner, newOwner);
        }

        creatorHookSettingsRegistry.transferPoolTypeWhitelistOwnership(listId, newOwner);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getPoolTypeWhitelistOwner(listId), newOwner);
        }

        vm.stopPrank();
    }

    // Handler for renouncePairTokenWhitelistOwnership
    function _executeRenouncePairTokenWhitelistOwnership(address caller, uint256 listId, bytes4 errorSelector)
        internal
    {
        vm.startPrank(caller);

        address currentOwner = creatorHookSettingsRegistry.getPairTokenWhitelistOwner(listId);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, false);
            emit ICreatorHookSettingsRegistry.PairTokenWhitelistOwnershipTransferred(listId, currentOwner, address(0));
        }

        creatorHookSettingsRegistry.renouncePairTokenWhitelistOwnership(listId);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getPairTokenWhitelistOwner(listId), address(0));
        }

        vm.stopPrank();
    }

    // Handler for renounceLpWhitelistOwnership
    function _executeRenounceLpWhitelistOwnership(address caller, uint256 listId, bytes4 errorSelector) internal {
        vm.startPrank(caller);

        address currentOwner = creatorHookSettingsRegistry.getLpWhitelistOwner(listId);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, false);
            emit ICreatorHookSettingsRegistry.LpWhitelistOwnershipTransferred(listId, currentOwner, address(0));
        }

        creatorHookSettingsRegistry.renounceLpWhitelistOwnership(listId);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getLpWhitelistOwner(listId), address(0));
        }

        vm.stopPrank();
    }

    // Handler for renouncePoolTypeWhitelistOwnership
    function _executeRenouncePoolTypeWhitelistOwnership(address caller, uint256 listId, bytes4 errorSelector)
        internal
    {
        vm.startPrank(caller);

        address currentOwner = creatorHookSettingsRegistry.getPoolTypeWhitelistOwner(listId);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, false);
            emit ICreatorHookSettingsRegistry.PoolTypeWhitelistOwnershipTransferred(listId, currentOwner, address(0));
        }

        creatorHookSettingsRegistry.renouncePoolTypeWhitelistOwnership(listId);

        if (errorSelector == bytes4(0)) {
            assertEq(creatorHookSettingsRegistry.getPoolTypeWhitelistOwner(listId), address(0));
        }

        vm.stopPrank();
    }

    function _executeSetTokenSettingsNoExtensions(
        address caller,
        address token,
        HookTokenSettings memory settings,
        address[] memory hooksToSync,
        bytes4 errorSelector
    ) internal {
        _executeSetTokenSettings(
            caller,
            token,
            settings,
            new bytes32[](0),
            new bytes[](0),
            new bytes32[](0),
            new bytes32[](0),
            hooksToSync,
            errorSelector
        );
    }

    function _executeSetTokenSettings(
        address caller,
        address token,
        HookTokenSettings memory settings,
        bytes32[] memory dataExtensions,
        bytes[] memory dataSettings,
        bytes32[] memory wordExtensions,
        bytes32[] memory wordSettings,
        address[] memory hooksToSync,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            HookTokenSettings memory expectedSettings = settings;
            expectedSettings.initialized = true;

            vm.expectEmit(true, false, false, true);
            emit ICreatorHookSettingsRegistry.TokenSettingsSet(token, expectedSettings);
        }

        creatorHookSettingsRegistry.setTokenSettings(
            token, settings, dataExtensions, dataSettings, wordExtensions, wordSettings, hooksToSync
        );

        if (errorSelector == bytes4(0)) {
            HookTokenSettings memory retrievedSettings = creatorHookSettingsRegistry.getTokenSettings(token);
            assertTrue(retrievedSettings.initialized);
            assertTrue(creatorHookSettingsRegistry.isTokenInitialized(token));

            if (dataExtensions.length > 0) {
                bytes[] memory retrievedData = creatorHookSettingsRegistry.getTokenExtendedData(token, dataExtensions);
                assertEq(retrievedData.length, dataSettings.length);
                for (uint256 i = 0; i < dataExtensions.length; i++) {
                    assertEq(retrievedData[i], dataSettings[i]);
                }
            }

            if (wordExtensions.length > 0) {
                bytes32[] memory retrievedWords =
                    creatorHookSettingsRegistry.getTokenExtendedWords(token, wordExtensions);
                assertEq(retrievedWords.length, wordSettings.length);
                for (uint256 i = 0; i < wordExtensions.length; i++) {
                    assertEq(retrievedWords[i], wordSettings[i]);
                }
            }
        }

        vm.stopPrank();
    }

    function _executeSetPricingBounds(
        address caller,
        address token,
        address[] memory pairTokens,
        uint160[] memory minSqrtPriceX96,
        uint160[] memory maxSqrtPriceX96,
        address[] memory hooksToSync,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            for (uint256 i = 0; i < pairTokens.length; i++) {
                if (minSqrtPriceX96[i] | maxSqrtPriceX96[i] == 0) {
                    vm.expectEmit(true, true, false, true);
                    emit IAMMStandardHook.PricingBoundsUnset(token, pairTokens[i]);
                } else {
                    vm.expectEmit(true, true, false, true);
                    emit IAMMStandardHook.PricingBoundsSet(token, pairTokens[i], minSqrtPriceX96[i], maxSqrtPriceX96[i]);
                }
            }
        }

        creatorHookSettingsRegistry.setPricingBounds(token, pairTokens, minSqrtPriceX96, maxSqrtPriceX96, hooksToSync);

        if (errorSelector == bytes4(0)) {
            for (uint256 i = 0; i < pairTokens.length; i++) {
                PricingBounds memory bounds = creatorHookSettingsRegistry.getPriceBounds(token, pairTokens[i]);
                assertEq(bounds.isSet, minSqrtPriceX96[i] | maxSqrtPriceX96[i] != 0);
                assertEq(bounds.minSqrtPriceX96, minSqrtPriceX96[i]);
                assertEq(bounds.maxSqrtPriceX96, maxSqrtPriceX96[i]);
            }
        }

        vm.stopPrank();
    }

    function _executeUpdatePairTokenWhitelist(
        address caller,
        uint256 listId,
        address[] memory tokens,
        bool add,
        address[] memory hooksToSync,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            // Note: We can't easily predict which tokens will actually be added/removed
            // since it depends on current state, so we'll verify after the call
        }

        creatorHookSettingsRegistry.updatePairTokenWhitelist(listId, tokens, add, hooksToSync);

        if (errorSelector == bytes4(0)) {
            // Verify tokens are in the expected state
            for (uint256 i = 0; i < tokens.length; i++) {
                assertEq(
                    creatorHookSettingsRegistry.isWhitelistedPairToken(listId, tokens[i]),
                    add,
                    "Token whitelist state mismatch"
                );
            }
        }

        vm.stopPrank();
    }

    function _executeUpdateLpWhitelist(
        address caller,
        uint256 listId,
        address[] memory accounts,
        bool add,
        address[] memory hooksToSync,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);

        creatorHookSettingsRegistry.updateLpWhitelist(listId, accounts, add, hooksToSync);

        if (errorSelector == bytes4(0)) {
            for (uint256 i = 0; i < accounts.length; i++) {
                assertEq(
                    creatorHookSettingsRegistry.isWhitelistedLp(listId, accounts[i]), add, "LP whitelist state mismatch"
                );
            }
        }

        vm.stopPrank();
    }

    function _executeUpdatePoolTypeWhitelist(
        address caller,
        uint256 listId,
        address[] memory poolTypes,
        bool add,
        address[] memory hooksToSync,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);

        creatorHookSettingsRegistry.updatePoolTypeWhitelist(listId, poolTypes, add, hooksToSync);

        if (errorSelector == bytes4(0)) {
            for (uint256 i = 0; i < poolTypes.length; i++) {
                assertEq(
                    creatorHookSettingsRegistry.isWhitelistedPoolType(listId, poolTypes[i]),
                    add,
                    "LP whitelist state mismatch"
                );
            }
        }

        vm.stopPrank();
    }

    //
    // Helper Functions - AMM Standard Hook
    //
    
    function _executeRegistryUpdateWhitelistPairToken(
        address caller,
        uint256 pairTokenWhitelistId,
        address[] memory pairTokens,
        bool pairTokensAdded,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);
        standardHook.registryUpdateWhitelistPairToken(pairTokenWhitelistId, pairTokens, pairTokensAdded);

        if (errorSelector == bytes4(0)) {
            for (uint256 i = 0; i < pairTokens.length; i++) {
                assertEq(
                    standardHook.isWhitelistedPairToken(pairTokenWhitelistId, pairTokens[i]),
                    pairTokensAdded,
                    "Pair token whitelist state mismatch"
                );
            }
        }

        vm.stopPrank();
    }

    function _executeRegistryUpdateWhitelistPoolType(
        address caller,
        uint256 poolTypeWhitelistId,
        address[] memory poolTypes,
        bool poolTypesAdded,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);
        standardHook.registryUpdateWhitelistPoolType(poolTypeWhitelistId, poolTypes, poolTypesAdded);

        vm.stopPrank();
    }

    function _executeRegistryUpdateWhitelistLpAddress(
        address caller,
        uint256 lpWhitelistId,
        address[] memory lpAddresses,
        bool lpAddressesAdded,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);
        standardHook.registryUpdateWhitelistLpAddress(lpWhitelistId, lpAddresses, lpAddressesAdded);

        if (errorSelector == bytes4(0)) {
            for (uint256 i = 0; i < lpAddresses.length; i++) {
                assertEq(
                    standardHook.isWhitelistedLiquidityProvider(lpWhitelistId, lpAddresses[i]),
                    lpAddressesAdded,
                    "LP whitelist state mismatch"
                );
            }
        }

        vm.stopPrank();
    }

    function _executeRegistryUpdateTokenSettings(
        address caller,
        address token,
        HookTokenSettings memory tokenSettings,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, false, false, true);
            emit IAMMStandardHook.TokenSettingsUpdated(token, tokenSettings);
        }

        standardHook.registryUpdateTokenSettings(token, tokenSettings);

        vm.stopPrank();
    }

    function _executeRegistryUpdatePricingBounds(
        address caller,
        address token,
        address[] memory pairTokens,
        uint160[] memory minSqrtPriceX96,
        uint160[] memory maxSqrtPriceX96,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            for (uint256 i = 0; i < pairTokens.length; i++) {
                if (minSqrtPriceX96[i] | maxSqrtPriceX96[i] == 0) {
                    vm.expectEmit(true, true, false, true);
                    emit IAMMStandardHook.PricingBoundsUnset(token, pairTokens[i]);
                } else {
                    vm.expectEmit(true, true, false, true);
                    emit IAMMStandardHook.PricingBoundsSet(token, pairTokens[i], minSqrtPriceX96[i], maxSqrtPriceX96[i]);
                }
            }
        }

        standardHook.registryUpdatePricingBounds(token, pairTokens, minSqrtPriceX96, maxSqrtPriceX96);

        vm.stopPrank();
    }

    function _executeRegistrySyncTokenSettings(address caller, address token, HookTokenSettings memory registrySettings, bytes4 errorSelector) internal {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, false, false, false);
            emit IAMMStandardHook.TokenSettingsUpdated(
                token,
                HookTokenSettings({
                    initialized: false,
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
                    tradingIsPaused: false
                })
            );
        }

        standardHook.registryUpdateTokenSettings(token, registrySettings);

        vm.stopPrank();
    }

    function _executeBeforeSwap(
        address caller,
        SwapContext memory context,
        HookSwapParams memory swapParams,
        bytes memory hookData,
        uint256 expectedInputFee,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);

        uint256 inputFee = standardHook.beforeSwap(context, swapParams, hookData);

        if (errorSelector == bytes4(0)) {
            assertEq(inputFee, expectedInputFee, "Input fee mismatch");
        }

        vm.stopPrank();
    }

    function _executeAfterSwap(
        address caller,
        SwapContext memory context,
        HookSwapParams memory swapParams,
        bytes memory hookData,
        uint256 expectedOutputFee,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);

        uint256 outputFee = standardHook.afterSwap(context, swapParams, hookData);

        if (errorSelector == bytes4(0)) {
            assertEq(outputFee, expectedOutputFee, "Output fee mismatch");
        }

        vm.stopPrank();
    }

    function _executeValidateAddLiquidity(
        address caller,
        bool hookForToken0,
        LiquidityContext memory context,
        LiquidityModificationParams memory liquidityParams,
        uint256 amount0,
        uint256 amount1,
        uint256 fees0,
        uint256 fees1,
        bytes memory hookData,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        if (errorSelector == AMMStandardHook__PoolDisabled.selector) {
            vm.expectRevert(abi.encodeWithSelector(AMMStandardHook__PoolDisabled.selector, liquidityParams.poolId));
        } else {
            _handleExpectRevert(errorSelector);
        }

        standardHook.validateAddLiquidity(
            hookForToken0, context, liquidityParams, amount0, amount1, fees0, fees1, hookData
        );

        vm.stopPrank();
    }

    function _executeValidateRemoveLiquidity(
        address caller,
        bool hookForToken0,
        LiquidityContext memory context,
        LiquidityModificationParams memory liquidityParams,
        uint256 amount0,
        uint256 amount1,
        uint256 fees0,
        uint256 fees1,
        bytes memory hookData,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);

        standardHook.validateRemoveLiquidity(
            hookForToken0, context, liquidityParams, amount0, amount1, fees0, fees1, hookData
        );

        vm.stopPrank();
    }

    function _executeValidatePoolCreation(
        address caller,
        address creator,
        bool hookForToken0,
        PoolCreationDetails memory details,
        bytes memory hookData,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        _handleExpectRevert(errorSelector);

        standardHook.validatePoolCreation(bytes32(0), creator, hookForToken0, details, hookData);

        vm.stopPrank();
    }
}