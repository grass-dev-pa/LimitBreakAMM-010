pragma solidity ^0.8.24;

import "./LBAMMCoreBase.t.sol";
import {StdStorage, stdStorage} from "forge-std/Test.sol";

contract LimitBreakAMMTest is LBAMMCoreBaseTest {
    MockPoolType public poolType;

    function setUp() public override {
        super.setUp();

        poolType = new MockPoolType();
        address poolTypeAddress = address(999);
        vm.etch(poolTypeAddress, address(poolType).code);
        poolType = MockPoolType(poolTypeAddress);
    }

    function test_collectHookFeesByTokenAndHook() public {
        _collectHookFeesByToken(address(usdc), address(usdc), address(usdc), alice, 0, bytes4(0));
        _collectHookFeesByHook(address(usdc), address(usdc), alice, 0, bytes4(0));
    }

    function test_setProtocolFees() public {
        changePrank(AMM_ADMIN);
        _setProtocolFees(1, 1, 1, bytes4(0));
    }

    function test_setProtocolFees_revert_LPFeeBPSTooHigh(uint16 lpFeeBPS) public {
        lpFeeBPS = uint16(bound(lpFeeBPS, MAX_BPS + 1, type(uint16).max));
        changePrank(AMM_ADMIN);
        _setProtocolFees(lpFeeBPS, 1000, 500, LBAMM__FeeAmountExceedsMaxFee.selector);
    }

    function test_setProtocolFees_revert_ExchangeFeeBPSTooHigh(uint16 exchangeFeeBPS) public {
        exchangeFeeBPS = uint16(bound(exchangeFeeBPS, MAX_BPS + 1, type(uint16).max));
        changePrank(AMM_ADMIN);
        _setProtocolFees(500, exchangeFeeBPS, 500, LBAMM__FeeAmountExceedsMaxFee.selector);
    }

    function test_setProtocolFees_revert_FeeOnTopBPSTooHigh(uint16 feeOnTopBPS) public {
        feeOnTopBPS = uint16(bound(feeOnTopBPS, MAX_BPS + 1, type(uint16).max));
        changePrank(AMM_ADMIN);
        _setProtocolFees(500, 500, feeOnTopBPS, LBAMM__FeeAmountExceedsMaxFee.selector);
    }

    function test_setProtocolFees_revert_NoFeeManagerRole() public {
        changePrank(alice);
        _setProtocolFees(500, 1000, 500, RoleClient__Unauthorized.selector);
    }

    function test_setFlashLoanFee() public {
        uint16 flashLoanFeeBPS = 10;
        changePrank(AMM_ADMIN);
        _setFlashLoanFee(flashLoanFeeBPS, bytes4(0));
    }

    function test_setTokenFees() public {
        uint16[] memory fees = new uint16[](2);
        fees[0] = 500;
        fees[1] = 1000;

        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(weth);

        changePrank(AMM_ADMIN);
        _setTokenFees(tokens, fees, bytes4(0));
    }

    function test_setTokenFees_revert_ArrayLengthMismatch() public {
        uint16[] memory fees = new uint16[](2);
        fees[0] = 500;
        fees[1] = 1000;

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        changePrank(AMM_ADMIN);
        vm.expectRevert(bytes4(LBAMM__ArrayLengthMismatch.selector));
        amm.setTokenFees(tokens, fees);
    }

    function test_createPool_revert_PoolAddressInvalid() public {
        PoolCreationDetails memory details = _createMockPoolDetails(address(usdc), address(usdc), address(weth));
        vm.expectRevert(bytes4(LBAMM__InvalidPoolType.selector));
        amm.createPool(details, bytes(""), bytes(""), bytes(""), bytes(""));
    }

    function test_createPool_revert_InvalidPoolID() public {
        PoolCreationDetails memory details = _createMockPoolDetails(address(poolType), address(usdc), address(weth));
        vm.expectRevert(bytes4(LBAMM__InvalidPoolId.selector));
        amm.createPool(details, bytes(""), bytes(""), bytes(""), bytes(""));
    }

    function test_createPool_revert_NoCodeAtTokenAddresses() public {
        PoolCreationDetails memory details = _createMockPoolDetails(address(poolType), address(0), address(weth));
        vm.expectRevert(bytes4(LBAMM__PoolCreationWithNoCodeAtToken.selector));
        amm.createPool(details, bytes(""), bytes(""), bytes(""), bytes(""));

        details.token0 = address(usdc);
        details.token1 = address(0);
        vm.expectRevert(bytes4(LBAMM__PoolCreationWithNoCodeAtToken.selector));
        amm.createPool(details, bytes(""), bytes(""), bytes(""), bytes(""));
    }

    function test_collectTokensOwedNoTokensOwed() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        _collectTokensOwed(alice, tokens, bytes4(0));
    }

    function test_setFeeOnTopProtocolFeeOverride() public {
        address recipient = address(0x123);
        bool enabled = true;
        uint16 feeBPS = 100;

        changePrank(AMM_ADMIN);
        _setFeeOnTopProtocolFeeOverride(recipient, enabled, feeBPS, bytes4(0));
    }

    function test_setFeeOnTopProtocolFeeOverride_revert_FeeAmountExceedsMaxFee() public {
        changePrank(AMM_ADMIN);
        _setFeeOnTopProtocolFeeOverride(address(111), true, 10_001, LBAMM__FeeAmountExceedsMaxFee.selector);
    }

    function test_setFeeOnTopProtocolFeeOverride_revert_NoFeeManagerRole() public {
        changePrank(alice);
        _setFeeOnTopProtocolFeeOverride(address(111), true, 100, RoleClient__Unauthorized.selector);
    }

    function test_setExchangeProtocolFeeOverride() public {
        address recipient = address(0x123);
        bool enabled = true;
        uint16 feeBPS = 100;

        changePrank(AMM_ADMIN);
        _setExchangeProtocolFeeOverride(recipient, enabled, feeBPS, bytes4(0));
    }

    function test_setExchangeProtocolFeeOverride_revert_FeeAmountExceedsMaxFee() public {
        changePrank(AMM_ADMIN);
        _setExchangeProtocolFeeOverride(address(111), true, 10_001, LBAMM__FeeAmountExceedsMaxFee.selector);
    }

    function test_setExchangeProtocolFeeOverride_revert_NoFeeManagerRole() public {
        changePrank(alice);
        _setExchangeProtocolFeeOverride(address(111), true, 100, RoleClient__Unauthorized.selector);
    }

    function test_setLPProtocolFeeOverride() public {
        bytes32 poolId = bytes32("111");
        bool enabled = true;
        uint16 feeBPS = 100;

        changePrank(AMM_ADMIN);
        _setLPProtocolFeeOverride(poolId, enabled, feeBPS, bytes4(0));
    }

    function test_setLPProtocolFeeOverride_revert_FeeAmountExceedsMaxFee() public {
        changePrank(AMM_ADMIN);
        _setLPProtocolFeeOverride(bytes32("111"), true, 10_001, LBAMM__FeeAmountExceedsMaxFee.selector);
    }

    function test_setLPProtocolFeeOverride_revert_NoFeeManagerRole() public {
        changePrank(alice);
        _setLPProtocolFeeOverride(bytes32("111"), true, 100, RoleClient__Unauthorized.selector);
    }

    function _createMockPoolDetails(address poolTypeAddr, address token0, address token1)
        private
        pure
        returns (PoolCreationDetails memory)
    {
        return PoolCreationDetails({
            poolType: poolTypeAddr,
            fee: 500,
            token0: token0,
            token1: token1,
            poolHook: address(0),
            poolParams: abi.encode("return0")
        });
    }
}

contract MockPoolType {
    function createPool(PoolCreationDetails memory details) external pure returns (bytes32) {
        if (keccak256(details.poolParams) == keccak256(abi.encode("return0"))) {
            return bytes32("0");
        } else {
            return bytes32("1");
        }
    }
}