pragma solidity ^0.8.24;

import "./ClobTransferHandler.t.sol";
import "../../hooks/AMMStandardHook.t.sol";


contract ClobTransferHandlerHookTest is ClobTransferHandlerTest, AMMStandardHookTest {
    address token0Owner;
    address token1Owner;

    function setUp() public virtual override(ClobTransferHandlerTest, AMMStandardHookTest) {
        super.setUp();

        token0Owner = token0.owner();
        token1Owner = token1.owner();

        HookTokenSettings memory settings;
        address[] memory hooksToSync = new address[](1);
        hooksToSync[0] = address(standardHook);

        changePrank(token0Owner);
        _setTokenSettings(
            address(token0),
            address(standardHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: true,
                addLiquidityHook: false,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: false,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: true
            }),
            bytes4(0)
        );
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

        changePrank(token1Owner);
        _setTokenSettings(
            address(token1),
            address(standardHook),
            TokenFlagSettings({
                beforeSwapHook: true,
                afterSwapHook: true,
                addLiquidityHook: false,
                removeLiquidityHook: false,
                collectFeesHook: false,
                poolCreationHook: false,
                hookManagesFees: false,
                flashLoans: false,
                flashLoansValidateFee: false,
                validateHandlerOrderHook: true
            }),
            bytes4(0)
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
    }

    function test_openOrder_revert_PriceOutsideBoundsToken0() public {
        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(token1);

        uint160[] memory minSqrtPriceX96 = new uint160[](1);
        minSqrtPriceX96[0] = 2**96 / 4;

        uint160[] memory maxSqrtPriceX96 = new uint160[](1);
        maxSqrtPriceX96[0] = 2**96;

        // set pricing bounds
        _executeRegistryUpdatePricingBounds(
            address(creatorHookSettingsRegistry),
            address(token0),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            bytes4(0)
        );

        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));
        _mintAndApprove(address(token1), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token1), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 2**96;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 snapshotId = vm.snapshot();

        // Price in bounds
        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );
        _openOrder(
            bob,
            address(token1),
            address(token0),
            uint160(uint256(2**192) / uint256(sqrtPriceX96)),
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        vm.revertTo(snapshotId);

        sqrtPriceX96 = 2**96 * 2;
        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );
        _openOrder(
            bob,
            address(token1),
            address(token0),
            uint160(uint256(2**192) / uint256(sqrtPriceX96)),
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );

        sqrtPriceX96 = 2**96 / 8;
        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );
        _openOrder(
            bob,
            address(token1),
            address(token0),
            uint160(uint256(2**192) / uint256(sqrtPriceX96)),
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );

        sqrtPriceX96 = 2**96 / 2;
        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );
        _openOrder(
            bob,
            address(token1),
            address(token0),
            uint160(uint256(2**192) / uint256(sqrtPriceX96)),
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );
    }

    function test_openOrder_revert_PriceOutsideBoundsToken1() public {
        address[] memory pairTokens = new address[](1);
        pairTokens[0] = address(token0);

        uint160[] memory minSqrtPriceX96 = new uint160[](1);
        minSqrtPriceX96[0] = 2**96 / 4;

        uint160[] memory maxSqrtPriceX96 = new uint160[](1);
        maxSqrtPriceX96[0] = 2**96;

        // set pricing bounds
        _executeRegistryUpdatePricingBounds(
            address(creatorHookSettingsRegistry),
            address(token1),
            pairTokens,
            minSqrtPriceX96,
            maxSqrtPriceX96,
            bytes4(0)
        );

        _mintAndApprove(address(token0), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token0), 1000 ether, bytes4(0));
        _mintAndApprove(address(token1), bob, address(clob), 1000 ether);
        _depositToken(bob, address(token1), 1000 ether, bytes4(0));

        uint160 sqrtPriceX96 = 2**96;
        uint256 orderAmount = 100 ether;
        bytes32 groupKey = clob.generateGroupKey(address(0), 1, 18);
        uint160 informationSqrtPriceX96 = 0;
        HooksExtraData memory hooksExtraData =
            HooksExtraData({tokenInHook: bytes(""), tokenOutHook: bytes(""), clobHook: bytes("")});

        uint256 snapshotId = vm.snapshot();

        // Price in bounds
        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );
        _openOrder(
            bob,
            address(token1),
            address(token0),
            uint160(uint256(2**192) / uint256(sqrtPriceX96)),
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );

        vm.revertTo(snapshotId);

        sqrtPriceX96 = 2**96 * 2;
        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );
        _openOrder(
            bob,
            address(token1),
            address(token0),
            uint160(uint256(2**192) / uint256(sqrtPriceX96)),
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );

        sqrtPriceX96 = 2**96 / 8;
        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );
        _openOrder(
            bob,
            address(token1),
            address(token0),
            uint160(uint256(2**192) / uint256(sqrtPriceX96)),
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(AMMStandardHook__InvalidPrice.selector)
        );

        sqrtPriceX96 = 2**96 / 2;
        _openOrder(
            bob,
            address(token0),
            address(token1),
            sqrtPriceX96,
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );
        _openOrder(
            bob,
            address(token1),
            address(token0),
            uint160(uint256(2**192) / uint256(sqrtPriceX96)),
            orderAmount,
            groupKey,
            informationSqrtPriceX96,
            hooksExtraData,
            bytes4(0)
        );
    }
}
