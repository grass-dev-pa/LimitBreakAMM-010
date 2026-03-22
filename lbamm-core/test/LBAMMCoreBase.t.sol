pragma solidity ^0.8.24;

// Forge Std Imports
import {Test, console2} from "forge-std/Test.sol";

import {Ownable} from "@limitbreak/tm-core-lib/src/utils/access/Ownable.sol";
import {Math} from "@limitbreak/tm-core-lib/src/utils/math/Math.sol";
import {SecureProxy} from "@limitbreak/secure-proxy/src/SecureProxy.sol";
import {SECURE_PROXY_CODE_MANAGER_BASE_ROLE, SECURE_PROXY_ADMIN_BASE_ROLE} from "@limitbreak/secure-proxy/src/Constants.sol";

import "../src/LimitBreakAMM.sol";

import "../src/interfaces/core/ILimitBreakAMMEvents.sol";
import "../src/interfaces/ILimitBreakAMMPoolType.sol";

import {ModuleAdmin} from "../src/modules/ModuleAdmin.sol";
import {ModuleLiquidity} from "../src/modules/ModuleLiquidity.sol";
import {ModuleFeeCollection} from "../src/modules/ModuleFeeCollection.sol";

import "../src/DataTypes.sol";
import "../src/libraries/FeeHelper.sol";
import "../src/libraries/PoolDecoder.sol";

import "./TestConstants.t.sol";

import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import "./mocks/WETHMock.sol";

import "@limitbreak/tm-role-server/src/RoleSetServer.sol";

import {IWrappedNative} from "@limitbreak/wrapped-native/interfaces/IWrappedNative.sol";
import {CreatorTokenTransferValidator} from "creator-token-transfer-validator/src/CreatorTokenTransferValidator.sol";

import "./mocks/WrappedNativeBytecode.sol";

contract LBAMMCoreBaseTest is Test {
    SecureProxy public ammProxy;
    LimitBreakAMM public amm;
    LimitBreakAMM private ammImpl;
    RoleSetServer public roleServer;
    CreatorTokenTransferValidator public transferValidator;

    ModuleAdmin public moduleAdmin;
    ModuleFeeCollection public moduleFeeCollection;
    ModuleLiquidity public moduleLiquidity;

    WETH9Mock public weth;
    ERC20Mock public usdc;
    ERC20Mock public currency2;
    ERC20Mock public currency3;
    ERC20Mock public currency4;
    IWrappedNative public wrappedNative;

    uint256 public adminKey;
    uint256 public aliceKey;
    uint256 public bobKey;
    uint256 public carolKey;
    uint256 public exchangeFeeRecipientKey;
    uint256 public feeOnTopRecipientKey;

    address public admin;
    address public alice;
    address public bob;
    address public carol;
    address public exchangeFeeRecipient;
    address public feeOnTopRecipient;

    event ExchangeProtocolFeeOverrideSet(address recipient, bool feeOverrideEnabled, uint16 protocolFeeBPS);
    event FeeOnTopProtocolFeeOverrideSet(address recipient, bool feeOverrideEnabled, uint16 protocolFeeBPS);
    event LPProtocolFeeOverrideSet(bytes32 poolId, bool feeOverrideEnabled, uint16 protocolFeeBPS);
    event LiquidityAdded(
        bytes32 indexed poolId, address indexed provider, uint256 amount0, uint256 amount1, uint256 fees0, uint256 fees1
    );
    event FeesCollected(bytes32 indexed poolId, address indexed provider, uint256 fees0, uint256 fees1);

    function setUp() public virtual {
        (admin, adminKey) = makeAddrAndKey("admin");
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        (carol, carolKey) = makeAddrAndKey("carol");
        (exchangeFeeRecipient, exchangeFeeRecipientKey) = makeAddrAndKey("exchangeFeeRecipient");
        (feeOnTopRecipient, feeOnTopRecipientKey) = makeAddrAndKey("feeOnTopRecipient");

        vm.deal(admin, 100 ether);

        WETH9Mock wethMock = new WETH9Mock();
        ERC20Mock usdcMock = new ERC20Mock("USD Coin", "USDC", 6);
        ERC20Mock currency2Mock = new ERC20Mock("Currency2", "CUR2", 18);
        ERC20Mock currency3Mock = new ERC20Mock("Currency3", "CUR3", 18);
        ERC20Mock currency4Mock = new ERC20Mock("Currency4", "CUR4", 18);

        vm.etch(WETH_ADDRESS, address(wethMock).code);
        vm.etch(USDC_ADDRESS, address(usdcMock).code);
        vm.etch(CURRENCY_2_ADDRESS, address(currency2Mock).code);
        vm.etch(CURRENCY_3_ADDRESS, address(currency3Mock).code);
        vm.etch(CURRENCY_4_ADDRESS, address(currency4Mock).code);
        vm.etch(WRAPPED_NATIVE_ADDRESS, WN_CODE);

        weth = WETH9Mock(WETH_ADDRESS);
        usdc = ERC20Mock(USDC_ADDRESS);
        currency2 = ERC20Mock(CURRENCY_2_ADDRESS);
        currency3 = ERC20Mock(CURRENCY_3_ADDRESS);
        currency4 = ERC20Mock(CURRENCY_4_ADDRESS);
        wrappedNative = IWrappedNative(WRAPPED_NATIVE_ADDRESS);

        CreatorTokenTransferValidator transferValidatorTmp =
            new CreatorTokenTransferValidator(AMM_ADMIN, address(1), "CreatorTokenTransferValidator", "4.0");
        vm.etch(PERMIT_C_VALIDATOR_ADDRESS, address(transferValidatorTmp).code);
        transferValidator = CreatorTokenTransferValidator(PERMIT_C_VALIDATOR_ADDRESS);
        vm.store(PERMIT_C_VALIDATOR_ADDRESS, keccak256(abi.encode(0, 10)), bytes32(uint256(uint160(AMM_ADMIN))));

        RoleSetServer roleServerTmp = new RoleSetServer();
        vm.etch(ROLE_SERVER, address(roleServerTmp).code);
        roleServer = RoleSetServer(ROLE_SERVER);
        changePrank(AMM_ADMIN);
        bytes32 roleSet = roleServer.createRoleSet(AMM_ROLE_SERVER_SET_SALT);

        roleServer.setRoleHolder(roleSet, LBAMM_FEE_MANAGER_BASE_ROLE, AMM_ADMIN, false, new IRoleClient[](0));
        roleServer.setRoleHolder(roleSet, LBAMM_FEE_RECEIVER_BASE_ROLE, AMM_FEE_RECEIVER, false, new IRoleClient[](0));
        roleServer.setRoleHolder(roleSet, SECURE_PROXY_CODE_MANAGER_BASE_ROLE, AMM_ADMIN, false, new IRoleClient[](0));
        roleServer.setRoleHolder(roleSet, SECURE_PROXY_ADMIN_BASE_ROLE, AMM_ADMIN, false, new IRoleClient[](0));

        ProtocolFeeStructure memory feeStructure =
            ProtocolFeeStructure({lpFeeBPS: 125, exchangeFeeBPS: 500, feeOnTopBPS: 2500});

        vm.warp(block.timestamp + 1);

        changePrank(KEYLESS_DEPLOYER);

        moduleLiquidity = new ModuleLiquidity{salt: MODULE_LIQUIDITY_SALT}(WRAPPED_NATIVE_ADDRESS);
        moduleAdmin = new ModuleAdmin{salt: MODULE_ADMIN_SALT}(WRAPPED_NATIVE_ADDRESS, address(roleServer), roleSet);
        moduleFeeCollection = new ModuleFeeCollection{salt: MODULE_FEE_COLLECTION_SALT}(WRAPPED_NATIVE_ADDRESS);

        ammImpl = new LimitBreakAMM{salt: AMM_SALT}(
            WRAPPED_NATIVE_ADDRESS,
            address(moduleLiquidity),
            address(moduleAdmin),
            address(moduleFeeCollection)
        );

        ammProxy = new SecureProxy{salt: AMM_PROXY_SALT}(
            address(ammImpl),
            address(roleServer),
            roleSet,
            bytes("")
        );
        
        amm = LimitBreakAMM(address(ammProxy));

        address[] memory whitelistAccounts = new address[](2);
        whitelistAccounts[0] = address(amm);
        changePrank(AMM_ADMIN);
        amm.setProtocolFees(feeStructure);
        transferValidator.addAccountsToWhitelist(0, whitelistAccounts);
        changePrank(address(this));

        vm.label(address(weth), "Wrapped Ether");
        vm.label(address(usdc), "USD Coin");
        vm.label(address(currency2), "Currency2");
        vm.label(address(currency3), "Currency3");
        vm.label(address(currency4), "Currency4");
        vm.label(address(amm), "LimitBreak AMM");
        vm.label(address(roleServer), "Role Server");
        vm.label(address(transferValidator), "Creator Token Transfer Validator");
        vm.label(address(wrappedNative), "Wrapped Native");
    }

    function changePrank(address msgSender) internal virtual override {
        vm.stopPrank();
        vm.startPrank(msgSender);
    }

    function _setProtocolFees(uint16 lpFeeBPS, uint16 exchangeFeeBPS, uint16 feeOnTopBPS, bytes4 errorSelector)
        internal
    {
        ProtocolFeeStructure memory feeStructure =
            ProtocolFeeStructure({lpFeeBPS: lpFeeBPS, exchangeFeeBPS: exchangeFeeBPS, feeOnTopBPS: feeOnTopBPS});

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, true);
            emit ILimitBreakAMMEvents.ProtocolFeesSet(lpFeeBPS, exchangeFeeBPS, feeOnTopBPS);
        }

        amm.setProtocolFees(feeStructure);

        if (errorSelector == bytes4(0)) {
            ProtocolFeeStructure memory currentFeeStructure = amm.getProtocolFeeStructure(address(0), address(0), bytes32(0));
            assertEq(currentFeeStructure.lpFeeBPS, lpFeeBPS, "LP Fee BPS mismatch");
            assertEq(currentFeeStructure.exchangeFeeBPS, exchangeFeeBPS, "Exchange Fee BPS mismatch");
            assertEq(currentFeeStructure.feeOnTopBPS, feeOnTopBPS, "Fee on Top BPS mismatch");
        }
    }

    function _setFlashLoanFee(uint16 flashLoanFeeBPS, bytes4 errorSelector) internal {
        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, true);
            emit ILimitBreakAMMEvents.FlashloanFeeSet(flashLoanFeeBPS);
        }

        amm.setFlashloanFee(flashLoanFeeBPS);

        if (errorSelector == bytes4(0)) {
            assertEq(amm.getFlashloanFeeBPS(), flashLoanFeeBPS, "Flash loan fee mismatch");
        }
    }

    function _setTokenFees(address[] memory tokens, uint16[] memory fees, bytes4 errorSelector) internal {
        _handleExpectRevert(errorSelector);

        amm.setTokenFees(tokens, fees);

        if (errorSelector == bytes4(0)) {
            for (uint256 i = 0; i < tokens.length; i++) {
                TokenSettings memory settings = amm.getTokenSettings(tokens[i]);
                assertEq(settings.hopFeeBPS, fees[i], "Token fee mismatch");
            }
        }
    }

    struct TokenFlagSettings {
        bool beforeSwapHook;
        bool afterSwapHook;
        bool addLiquidityHook;
        bool removeLiquidityHook;
        bool collectFeesHook;
        bool poolCreationHook;
        bool hookManagesFees;
        bool flashLoans;
        bool flashLoansValidateFee;
        bool validateHandlerOrderHook;
    }

    function _packSettings(TokenFlagSettings memory settings) internal pure returns (uint32 packedSettings) {
        if (settings.beforeSwapHook) packedSettings |= TOKEN_SETTINGS_BEFORE_SWAP_HOOK_FLAG;
        if (settings.afterSwapHook) packedSettings |= TOKEN_SETTINGS_AFTER_SWAP_HOOK_FLAG;
        if (settings.addLiquidityHook) packedSettings |= TOKEN_SETTINGS_ADD_LIQUIDITY_HOOK_FLAG;
        if (settings.removeLiquidityHook) packedSettings |= TOKEN_SETTINGS_REMOVE_LIQUIDITY_HOOK_FLAG;
        if (settings.collectFeesHook) packedSettings |= TOKEN_SETTINGS_COLLECT_FEES_HOOK_FLAG;
        if (settings.poolCreationHook) packedSettings |= TOKEN_SETTINGS_POOL_CREATION_HOOK_FLAG;
        if (settings.hookManagesFees) packedSettings |= TOKEN_SETTINGS_HOOK_MANAGES_FEES_FLAG;
        if (settings.flashLoans) packedSettings |= TOKEN_SETTINGS_FLASHLOANS_FLAG;
        if (settings.flashLoansValidateFee) packedSettings |= TOKEN_SETTINGS_FLASHLOANS_VALIDATE_FEE_FLAG;
        if (settings.validateHandlerOrderHook) packedSettings |= TOKEN_SETTINGS_HANDLER_ORDER_VALIDATE_FLAG;

        return packedSettings;
    }

    function _setTokenSettings(address token, address hook, TokenFlagSettings memory settings, bytes4 errorSelector)
        internal
    {
        uint32 packedSettings = _packSettings(settings);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, true);
            emit ILimitBreakAMMEvents.TokenSettingsUpdated(token, hook, packedSettings);
        }
        amm.setTokenSettings(token, hook, packedSettings);

        if (errorSelector == bytes4(0)) {
            TokenSettings memory currentSettings = amm.getTokenSettings(token);
            assertEq(currentSettings.tokenHook, hook, "Token hook mismatch");
            assertEq(currentSettings.packedSettings, packedSettings, "Token flags mismatch");
        }
    }

    function _setFeeOnTopProtocolFeeOverride(
        address recipient_,
        bool overrideEnabled_,
        uint16 bps_,
        bytes4 errorSelector
    ) internal {
        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, true);
            emit FeeOnTopProtocolFeeOverrideSet(recipient_, overrideEnabled_, bps_);
        }

        amm.setFeeOnTopProtocolFeeOverride(recipient_, overrideEnabled_, bps_);

        if (errorSelector == bytes4(0)) {
            ProtocolFeeStructure memory baseFees = amm.getProtocolFeeStructure(address(0), address(0), bytes32(0));
            ProtocolFeeStructure memory feeOverride = amm.getProtocolFeeStructure(address(0), recipient_, bytes32(0));
            if (overrideEnabled_) {
                assertEq(baseFees.feeOnTopBPS == feeOverride.feeOnTopBPS, baseFees.feeOnTopBPS == bps_);
                assertEq(feeOverride.feeOnTopBPS, bps_);
            } else {
                assertEq(feeOverride.feeOnTopBPS, baseFees.feeOnTopBPS);
            }
        }
    }

    function _setExchangeProtocolFeeOverride(
        address recipient_,
        bool overrideEnabled_,
        uint16 bps_,
        bytes4 errorSelector
    ) internal {
        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, true);
            emit ExchangeProtocolFeeOverrideSet(recipient_, overrideEnabled_, bps_);
        }

        amm.setExchangeProtocolFeeOverride(recipient_, overrideEnabled_, bps_);

        if (errorSelector == bytes4(0)) {
            ProtocolFeeStructure memory baseFees = amm.getProtocolFeeStructure(address(0), address(0), bytes32(0));
            ProtocolFeeStructure memory feeOverride = amm.getProtocolFeeStructure(recipient_, address(0), bytes32(0));
            if (overrideEnabled_) {
                assertEq(baseFees.exchangeFeeBPS == feeOverride.exchangeFeeBPS, baseFees.exchangeFeeBPS == bps_);
                assertEq(feeOverride.exchangeFeeBPS, bps_);
            } else {
                assertEq(feeOverride.exchangeFeeBPS, baseFees.exchangeFeeBPS);
            }
        }
    }

    function _setLPProtocolFeeOverride(bytes32 poolId_, bool overrideEnabled_, uint16 bps_, bytes4 errorSelector)
        internal
    {
        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, true);
            emit LPProtocolFeeOverrideSet(poolId_, overrideEnabled_, bps_);
        }

        amm.setLPProtocolFeeOverride(poolId_, overrideEnabled_, bps_);

        if (errorSelector == bytes4(0)) {
            ProtocolFeeStructure memory baseFees = amm.getProtocolFeeStructure(address(0), address(0), bytes32(0));
            ProtocolFeeStructure memory feeOverride = amm.getProtocolFeeStructure(address(0), address(0), poolId_);
            if (overrideEnabled_) {
                assertEq(baseFees.lpFeeBPS == feeOverride.lpFeeBPS, baseFees.lpFeeBPS == bps_);
                assertEq(feeOverride.lpFeeBPS, bps_);
            } else {
                assertEq(feeOverride.lpFeeBPS, baseFees.lpFeeBPS);
            }
        }
    }

    function _collectProtocolFees(address[] memory tokens, bytes4 errorSelector) internal {
        uint256[] memory expectedFees = new uint256[](tokens.length);
        uint256[] memory balancesBefore = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            balancesBefore[i] = IERC20(tokens[i]).balanceOf(address(AMM_FEE_RECEIVER));
            expectedFees[i] = amm.getProtocolFees(tokens[i]);
        }

        if (errorSelector != bytes4(0)) {
            vm.expectRevert(errorSelector);
        }
        amm.collectProtocolFees(tokens);

        if (errorSelector == bytes4(0)) {
            for (uint256 i = 0; i < tokens.length; i++) {
                uint256 balanceAfter = IERC20(tokens[i]).balanceOf(address(AMM_FEE_RECEIVER));
                assertEq(balanceAfter, balancesBefore[i] + expectedFees[i], "Collected fees mismatch");
                assertEq(amm.getProtocolFees(tokens[i]), 0, "Protocol fees should be zero after collecting");
            }
        }
    }

    function _collectTokensOwed(address sender, address[] memory tokens, bytes4 errorSelector) internal {
        changePrank(sender);
        uint256[] memory tokensOwed = new uint256[](tokens.length);
        uint256[] memory balancesBefore = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokensOwed[i] = amm.getTokensOwed(sender, tokens[i]);
            balancesBefore[i] = IERC20(tokens[i]).balanceOf(sender);
        }

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            for (uint256 i = 0; i < tokens.length; i++) {
                if (tokensOwed[i] > 0) {
                    vm.expectEmit(true, true, true, true);
                    emit ILimitBreakAMMEvents.TokensClaimed(sender, tokens[i], tokensOwed[i]);
                }
            }
        }
        amm.collectTokensOwed(tokens);

        if (errorSelector == bytes4(0)) {
            for (uint256 i = 0; i < tokens.length; i++) {
                uint256 balanceAfter = IERC20(tokens[i]).balanceOf(sender);
                assertEq(balanceAfter - balancesBefore[i], tokensOwed[i], "Collected tokens owed mismatch");
            }
        }
    }

    function _collectHookFeesByToken(
        address sender,
        address tokenFor,
        address tokenFee,
        address recipient,
        uint256 amount,
        bytes4 errorSelector
    ) internal {
        changePrank(sender);

        uint256 amountOwedBefore = amm.getHookFeesOwedByToken(tokenFor, tokenFee);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, true);
            emit ILimitBreakAMMEvents.TokensClaimed(recipient, tokenFee, amount);
        }

        amm.collectHookFeesByToken(tokenFor, tokenFee, recipient, amount);

        if (errorSelector == bytes4(0)) {
            uint256 amountOwedAfter = amm.getHookFeesOwedByToken(tokenFor, tokenFee);
            assertEq(amountOwedBefore - amountOwedAfter, amount, "Hook fees should be zero after collecting");
        }
    }

    function _collectHookFeesByHook(
        address sender,
        address tokenFee,
        address recipient,
        uint256 amount,
        bytes4 errorSelector
    ) internal {
        changePrank(sender);

        if (errorSelector != bytes4(0)) {
            _handleExpectRevert(errorSelector);
        } else {
            vm.expectEmit(true, true, true, true);
            emit ILimitBreakAMMEvents.TokensClaimed(recipient, tokenFee, amount);
        }

        uint256 amountOwedBefore = amm.getHookFeesOwedByHook(sender, tokenFee, tokenFee);

        amm.collectHookFeesByHook(tokenFee, tokenFee, recipient, amount);

        if (errorSelector == bytes4(0)) {
            uint256 amountOwedAfter = amm.getHookFeesOwedByHook(sender, tokenFee, recipient);
            assertEq(amountOwedBefore - amountOwedAfter, amount, "Hook fees should be zero after collecting");
        }
    }

    function _executeFlashLoan(FlashloanRequest calldata request, bytes4 errorSelector) internal {
        _handleExpectRevert(errorSelector);
        amm.flashLoan(request);
    }

    function _mintAndApprove(address token, address receiver, address spender, uint256 amount) internal {
        ERC20Mock(token).mint(receiver, amount);
        changePrank(receiver);
        IERC20(token).approve(spender, amount);
    }

    function _dealDepositApproveNative(address receiver, address spender, uint256 amount) internal {
        vm.deal(receiver, amount);
        changePrank(receiver);
        wrappedNative.deposit{value: amount}();
        wrappedNative.approve(spender, amount);
    }

    function _getProtocolFeeLPBPS() internal view returns (uint16) {
        return amm.getProtocolFeeStructure(address(0), address(0), bytes32(0)).lpFeeBPS;
    }

    function _handleExpectRevert(bytes4 errorSelector) internal {
        if (errorSelector != bytes4(0)) {
            if (errorSelector == bytes4(PANIC_SELECTOR)) {
                vm.expectRevert();
            } else {
                vm.expectRevert(errorSelector);
            }
        }
    }

    function _calculatePriceLimit(uint256 amount1, uint256 amount0) internal pure returns (uint160 sqrtPriceX96) {
        console2.log("token1: ", amount1);
        console2.log("token0: ", amount0);
        if (amount1 == 0 || amount0 == 0) {
            return 0;
        }

        uint256 maxMultiplier = type(uint256).max / amount1;
        uint256 multiplier;
        uint256 n = 96;
        while (true) {
            multiplier = 2 ** (n << 1);
            if (maxMultiplier > multiplier) {
                break;
            }
            --n;
        }

        unchecked {
            uint256 tmpPrice = _sqrt(amount1 * multiplier / amount0) * (2 ** (96 - n));
            if (tmpPrice > type(uint160).max) {
                return 0;
            }
            sqrtPriceX96 = uint160(tmpPrice);
        }
    }

    /// @dev Returns the square root of `x`, rounded down.
    function _sqrt(uint256 x) internal pure returns (uint256 z) {
        /// @solidity memory-safe-assembly
        assembly {
            // `floor(sqrt(2**15)) = 181`. `sqrt(2**15) - 181 = 2.84`.
            z := 181 // The "correct" value is 1, but this saves a multiplication later.

            // This segment is to get a reasonable initial estimate for the Babylonian method. With a bad
            // start, the correct # of bits increases ~linearly each iteration instead of ~quadratically.

            // Let `y = x / 2**r`. We check `y >= 2**(k + 8)`
            // but shift right by `k` bits to ensure that if `x >= 256`, then `y >= 256`.
            let r := shl(7, lt(0xffffffffffffffffffffffffffffffffff, x))
            r := or(r, shl(6, lt(0xffffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffffff, shr(r, x))))
            r := or(r, shl(4, lt(0xffffff, shr(r, x))))
            z := shl(shr(1, r), z)

            // Goal was to get `z*z*y` within a small factor of `x`. More iterations could
            // get y in a tighter range. Currently, we will have y in `[256, 256*(2**16))`.
            // We ensured `y >= 256` so that the relative difference between `y` and `y+1` is small.
            // That's not possible if `x < 256` but we can just verify those cases exhaustively.

            // Now, `z*z*y <= x < z*z*(y+1)`, and `y <= 2**(16+8)`, and either `y >= 256`, or `x < 256`.
            // Correctness can be checked exhaustively for `x < 256`, so we assume `y >= 256`.
            // Then `z*sqrt(y)` is within `sqrt(257)/sqrt(256)` of `sqrt(x)`, or about 20bps.

            // For `s` in the range `[1/256, 256]`, the estimate `f(s) = (181/1024) * (s+1)`
            // is in the range `(1/2.84 * sqrt(s), 2.84 * sqrt(s))`,
            // with largest error when `s = 1` and when `s = 256` or `1/256`.

            // Since `y` is in `[256, 256*(2**16))`, let `a = y/65536`, so that `a` is in `[1/256, 256)`.
            // Then we can estimate `sqrt(y)` using
            // `sqrt(65536) * 181/1024 * (a + 1) = 181/4 * (y + 65536)/65536 = 181 * (y + 65536)/2**18`.

            // There is no overflow risk here since `y < 2**136` after the first branch above.
            z := shr(18, mul(z, add(shr(r, x), 65536))) // A `mul()` is saved from starting `z` at 181.

            // Given the worst case multiplicative error of 2.84 above, 7 iterations should be enough.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // If `x+1` is a perfect square, the Babylonian method cycles between
            // `floor(sqrt(x))` and `ceil(sqrt(x))`. This statement ensures we return floor.
            // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
            z := sub(z, lt(div(x, z), z))
        }
    }
}
