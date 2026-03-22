pragma solidity ^0.8.24;

import "./DynamicPool.t.sol";

contract DynamicPoolCrossTickTest is DynamicPoolTest {

    function setUp() public virtual override {
        super.setUp();
    }

    

    function test_singleSwap_swapByInputZeroForOne_CrossTick() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addDynamicLiquidityPositionsAcrossTickBoundaries(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _mintAndApprove(address(usdc), alice, address(amm), 10_000_000e6);
        _executeDynamicPoolSingleSwap(
            _createSwapOrder(alice, 220_000e6, 0, address(usdc), address(weth), block.timestamp + 1),
            poolId,
            exchangeFee,
            feeOnTop,
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }

    function test_singleSwap_swapByInputOneForZero_CrossTick() public {
        bytes32 poolId = _createStandardDynamicPool();

        _addDynamicLiquidityPositionsAcrossTickBoundaries(poolId);

        BPSFeeWithRecipient memory exchangeFee = BPSFeeWithRecipient({BPS: 0, recipient: address(0)});

        FlatFeeWithRecipient memory feeOnTop = FlatFeeWithRecipient({amount: 0, recipient: address(0)});

        _mintAndApprove(address(weth), alice, address(amm), 10_000_000 ether);
        _executeDynamicPoolSingleSwap(
            _createSwapOrder(alice, 5000e6, 0, address(weth), address(usdc), block.timestamp + 1),
            poolId,
            exchangeFee,
            feeOnTop,
            _emptySwapHooksExtraData(),
            bytes(""),
            bytes4(0)
        );
    }
}