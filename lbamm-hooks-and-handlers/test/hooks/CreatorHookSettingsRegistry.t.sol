pragma solidity ^0.8.24;

import "../HooksAndHandlersBase.t.sol";

contract CreatorHookSettingsRegistryTest is HooksAndHandlersBaseTest {

    event PairTokenWhitelistCreated(uint256 indexed listId, address indexed creator, string whitelistName);
    event LpWhitelistCreated(uint256 indexed listId, address indexed creator, string whitelistName);
    event PoolTypeWhitelistCreated(uint256 indexed listId, address indexed creator, string whitelistName);
    event PairTokenWhitelistOwnershipTransferred(
        uint256 indexed listId, address indexed previousOwner, address indexed newOwner
    );
    event LpWhitelistOwnershipTransferred(
        uint256 indexed listId, address indexed previousOwner, address indexed newOwner
    );
    event PoolTypeWhitelistOwnershipTransferred(
        uint256 indexed listId, address indexed previousOwner, address indexed newOwner
    );
    event TokenSettingsSet(address indexed token, HookTokenSettings settings);
    event PricingBoundsSet(
        address indexed token, address indexed pairToken, uint160 minSqrtPriceX96, uint160 maxSqrtPriceX96
    );
    event ExpansionWordsSet(address indexed token, bytes32 indexed key, bytes32 value);
    event ExpansionDatumsSet(address indexed token, bytes32 indexed key, bytes data);
    event PairTokenWhitelistUpdated(uint256 indexed listId, address indexed token, bool added);
    event LpWhitelistUpdated(uint256 indexed listId, address indexed account, bool added);

    function setUp() public virtual override {
        super.setUp();
    }

    function test_updatePairTokenWhitelist() public {
        uint256 listId = _executeCreatePairTokenWhitelist(testToken.owner(), "Test Pair Token Whitelist", bytes4(0));
        address[] memory tokensToAdd = new address[](2);
        tokensToAdd[0] = address(usdc);
        tokensToAdd[1] = address(weth);

        _executeUpdatePairTokenWhitelist(testToken.owner(), listId, tokensToAdd, true, new address[](0), bytes4(0));

        _executeUpdatePairTokenWhitelist(testToken.owner(), listId, tokensToAdd, false, new address[](0), bytes4(0));
    }

    function test_updatePoolTypeWhitelist() public {
        uint256 listId = _executeCreatePoolTypeWhitelist(testToken.owner(), "Test Pool Type Whitelist", bytes4(0));
        address[] memory poolTypesToAdd = new address[](2);
        poolTypesToAdd[0] = address(usdc);
        poolTypesToAdd[1] = address(weth);

        _executeUpdatePoolTypeWhitelist(testToken.owner(), listId, poolTypesToAdd, true, new address[](0), bytes4(0));

        _executeUpdatePoolTypeWhitelist(testToken.owner(), listId, poolTypesToAdd, false, new address[](0), bytes4(0));
    }

    function test_updateLpWhitelist() public {
        uint256 listId = _executeCreateLpWhitelist(testToken.owner(), "Test Pool Type Whitelist", bytes4(0));
        address[] memory lp = new address[](2);
        lp[0] = address(alice);
        lp[1] = address(bob);

        _executeUpdateLpWhitelist(testToken.owner(), listId, lp, true, new address[](0), bytes4(0));

        _executeUpdateLpWhitelist(testToken.owner(), listId, lp, false, new address[](0), bytes4(0));
    }

    function test_setExpansionSettingsOfCollection() public {
        ExpansionWord[] memory expansionWords = new ExpansionWord[](2);
        expansionWords[0] = ExpansionWord({key: bytes32("wordKey1"), value: bytes32("wordValue1")});
        expansionWords[1] = ExpansionWord({key: bytes32("wordKey2"), value: bytes32("wordValue2")});

        ExpansionDatum[] memory expansionDatums = new ExpansionDatum[](2);
        expansionDatums[0] = ExpansionDatum({key: bytes32("datumKey1"), value: "datumValue1"});
        expansionDatums[1] = ExpansionDatum({key: bytes32("datumKey2"), value: "datumValue2"});

        _executeSetExpansionSettingsOfCollection(
            currency2.owner(), address(currency2), expansionWords, expansionDatums, bytes4(0)
        );
    }

    function _executeSetExpansionSettingsOfCollection(
        address caller,
        address token,
        ExpansionWord[] memory expansionWords,
        ExpansionDatum[] memory expansionDatums,
        bytes4 errorSelector
    ) internal {
        vm.startPrank(caller);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            // Expect ExpansionWordsSet events
            for (uint256 i = 0; i < expansionWords.length; i++) {
                vm.expectEmit(true, true, false, true);
                emit ExpansionWordsSet(token, expansionWords[i].key, expansionWords[i].value);
            }

            // Expect ExpansionDatumsSet events
            for (uint256 i = 0; i < expansionDatums.length; i++) {
                vm.expectEmit(true, true, false, true);
                emit ExpansionDatumsSet(token, expansionDatums[i].key, expansionDatums[i].value);
            }
        }

        creatorHookSettingsRegistry.setExpansionSettingsOfCollection(token, expansionWords, expansionDatums);

        if (errorSelector == bytes4(0)) {
            if (expansionWords.length > 0) {
                bytes32[] memory wordKeys = new bytes32[](expansionWords.length);
                for (uint256 i = 0; i < expansionWords.length; i++) {
                    wordKeys[i] = expansionWords[i].key;
                }

                bytes32[] memory retrievedWords = creatorHookSettingsRegistry.getTokenExtendedWords(token, wordKeys);
                assertEq(retrievedWords.length, expansionWords.length);
                for (uint256 i = 0; i < expansionWords.length; i++) {
                    assertEq(retrievedWords[i], expansionWords[i].value);
                }
            }

            if (expansionDatums.length > 0) {
                bytes32[] memory datumKeys = new bytes32[](expansionDatums.length);
                for (uint256 i = 0; i < expansionDatums.length; i++) {
                    datumKeys[i] = expansionDatums[i].key;
                }

                bytes[] memory retrievedData = creatorHookSettingsRegistry.getTokenExtendedData(token, datumKeys);
                assertEq(retrievedData.length, expansionDatums.length);
                for (uint256 i = 0; i < expansionDatums.length; i++) {
                    assertEq(retrievedData[i], expansionDatums[i].value);
                }
            }
        }

        vm.stopPrank();
    }

    function test_setPricingBounds() public {

        address[] memory pairTokens = new address[](2);
        pairTokens[0] = address(usdc);
        pairTokens[1] = address(weth);

        uint160[] memory minSqrtPriceX96 = new uint160[](2);
        minSqrtPriceX96[0] = 1e12;
        minSqrtPriceX96[1] = 2e12;
        uint160[] memory maxSqrtPriceX96 = new uint160[](2);
        maxSqrtPriceX96[0] = 1e18;
        maxSqrtPriceX96[1] = 2e18;

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetPricingBounds(
            testToken.owner(),
            address(testToken),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            hooksToSync,
            bytes4(0) // No error expected
        );

        minSqrtPriceX96[0] = 1e12+1;
        minSqrtPriceX96[1] = 0;
        maxSqrtPriceX96[0] = 1e18+1;
        maxSqrtPriceX96[1] = 0;
        // Unset one token
        _executeSetPricingBounds(
            testToken.owner(),
            address(testToken),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            hooksToSync,
            bytes4(0) // No error expected
        );
    }

    function test_setPricingBounds_revert_mismatchedArrayLengths() public {

        address[] memory pairTokens = new address[](2);
        pairTokens[0] = address(usdc);
        pairTokens[1] = address(weth);

        uint160[] memory minSqrtPriceX96 = new uint160[](1);
        minSqrtPriceX96[0] = 1e12;
        uint160[] memory maxSqrtPriceX96 = new uint160[](2);
        maxSqrtPriceX96[0] = 1e18;
        maxSqrtPriceX96[1] = 2e18;

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetPricingBounds(
            testToken.owner(),
            address(testToken),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            hooksToSync,
            bytes4(CreatorHookSettingsRegistry__LengthOfProvidedArraysMismatch.selector)
        );
    }

    function test_setPricingBounds_revert_MaxPriceBelowMinPrice() public {

        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(usdc);

        uint160[] memory minSqrtPriceX96 = new uint160[](1);
        minSqrtPriceX96[0] = 2e18;
        uint160[] memory maxSqrtPriceX96 = new uint160[](1);
        maxSqrtPriceX96[0] = 1e18;

        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetPricingBounds(
            testToken.owner(),
            address(testToken),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            hooksToSync,
            bytes4(CreatorHookSettingsRegistry__MaxPriceMustBeGreaterThanOrEqualToMinPrice.selector)
        );
    }

    function test_setTokenSettings() public {

        HookTokenSettings memory settings = HookTokenSettings({
            initialized: false,
            blockDirectSwaps: false,
            checkDisabledPools: false,
            tokenFeeBuyBPS: 10,
            tokenFeeSellBPS: 15,
            pairedFeeBuyBPS: 25,
            pairedFeeSellBPS: 30,
            poolTypeWhitelistId: 0,
            minFeeAmount: 1,
            maxFeeAmount: 1,
            pairedTokenWhitelistId: 0,
            lpWhitelistId: 0,
            tradingIsPaused: false
        });

        // Test data extensions
        bytes32[] memory dataExtensions = new bytes32[](2);
        dataExtensions[0] = bytes32("dataKey1");
        dataExtensions[1] = bytes32("dataKey2");

        bytes[] memory dataSettings = new bytes[](2);
        dataSettings[0] = abi.encode("test data 1");
        dataSettings[1] = abi.encode("test data 2");

        // Test word extensions
        bytes32[] memory wordExtensions = new bytes32[](2);
        wordExtensions[0] = bytes32("wordKey1");
        wordExtensions[1] = bytes32("wordKey2");

        bytes32[] memory wordSettings = new bytes32[](2);
        wordSettings[0] = bytes32("word1");
        wordSettings[1] = bytes32("word2");

        // Test hooks to sync
        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        _executeSetTokenSettings(
            testToken.owner(),
            address(testToken),
            settings,
            dataExtensions,
            dataSettings,
            wordExtensions,
            wordSettings,
            hooksToSync,
            bytes4(0) // No error expected
        );

        _executeSetTokenSettings(
            address(testToken),
            address(testToken),
            settings,
            dataExtensions,
            dataSettings,
            wordExtensions,
            wordSettings,
            hooksToSync,
            bytes4(0) // No error expected
        );
    }

    function test_createPairTokenWhitelist() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Whitelist";

        _executeCreatePairTokenWhitelist(creator, whitelistName, bytes4(0));
    }

    function test_createLpWhitelist() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Lp Whitelist";

        _executeCreateLpWhitelist(creator, whitelistName, bytes4(0));
    }

    function test_createPoolTypeWhitelist() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Pool Type Whitelist";

        _executeCreatePoolTypeWhitelist(creator, whitelistName, bytes4(0));
    }

    function test_transferPairTokenWhitelistOwnership() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Whitelist";
        uint256 listId = _executeCreatePairTokenWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(0x456);
        _executeTransferPairTokenWhitelistOwnership(creator, listId, newOwner, bytes4(0));
    }

    function test_transferLpWhitelistOwnership() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Lp Whitelist";
        uint256 listId = _executeCreateLpWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(0x456);
        _executeTransferLpWhitelistOwnership(creator, listId, newOwner, bytes4(0));
    }

    function test_transferPoolTypeWhitelistOwnership() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Pool Type Whitelist";
        uint256 listId = _executeCreatePoolTypeWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(0x456);
        _executeTransferPoolTypeWhitelistOwnership(creator, listId, newOwner, bytes4(0));
    }

    function test_transferPairTokenWhitelistOwnership_revert_address0() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Whitelist";
        uint256 listId = _executeCreatePairTokenWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(0);
        _executeTransferPairTokenWhitelistOwnership(
            creator, listId, newOwner, bytes4(CreatorHookSettingsRegistry__InvalidOwner.selector)
        );
    }

    function test_transferLpWhitelistOwnership_revert_address0() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Lp Whitelist";
        uint256 listId = _executeCreateLpWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(0);
        _executeTransferLpWhitelistOwnership(
            creator, listId, newOwner, bytes4(CreatorHookSettingsRegistry__InvalidOwner.selector)
        );
    }

    function test_transferPoolTypeWhitelistOwnership_revert_address0() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Pool Type Whitelist";
        uint256 listId = _executeCreatePoolTypeWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(0);
        _executeTransferPoolTypeWhitelistOwnership(
            creator, listId, newOwner, bytes4(CreatorHookSettingsRegistry__InvalidOwner.selector)
        );
    }

    function test_transferPairTokenWhitelistOwnership_revert_notOwner() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Whitelist";
        uint256 listId = _executeCreatePairTokenWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(111);
        _executeTransferPairTokenWhitelistOwnership(
            alice, listId, newOwner, bytes4(CreatorHookSettingsRegistry__CallerDoesNotOwnPairTokenWhitelist.selector)
        );
    }

    function test_transferLpWhitelistOwnership_revert_notOwner() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Lp Whitelist";
        uint256 listId = _executeCreateLpWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(1111);
        _executeTransferLpWhitelistOwnership(
            alice, listId, newOwner, bytes4(CreatorHookSettingsRegistry__CallerDoesNotOwnLpWhitelist.selector)
        );
    }

    function test_transferPoolTypeWhitelistOwnership_revert_notOwner() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Pool Type Whitelist";
        uint256 listId = _executeCreatePoolTypeWhitelist(creator, whitelistName, bytes4(0));

        address newOwner = address(111);
        _executeTransferPoolTypeWhitelistOwnership(
            alice, listId, newOwner, bytes4(CreatorHookSettingsRegistry__CallerDoesNotOwnPoolTypeWhitelist.selector)
        );
    }

    function test_renouncePairTokenWhitelistOwnership() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Whitelist";
        uint256 listId = _executeCreatePairTokenWhitelist(creator, whitelistName, bytes4(0));

        _executeRenouncePairTokenWhitelistOwnership(creator, listId, bytes4(0));
    }

    function test_renounceLpWhitelistOwnership() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Lp Whitelist";
        uint256 listId = _executeCreateLpWhitelist(creator, whitelistName, bytes4(0));

        _executeRenounceLpWhitelistOwnership(creator, listId, bytes4(0));
    }

    function test_renouncePoolTypeWhitelistOwnership() public {
        address creator = address(0x123);
        string memory whitelistName = "Test Pool Type Whitelist";
        uint256 listId = _executeCreatePoolTypeWhitelist(creator, whitelistName, bytes4(0));

        _executeRenouncePoolTypeWhitelistOwnership(creator, listId, bytes4(0));
    }
}