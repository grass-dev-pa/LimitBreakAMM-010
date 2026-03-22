//SPDX-License-Identifier: LicenseRef-PolyForm-Strict-1.0.0
pragma solidity 0.8.24;

import "./Constants.sol";
import "./Errors.sol";
import "./interfaces/ISingleProviderPoolType.sol";
import "./interfaces/ISingleProviderPoolHook.sol";
import "./libraries/SingleProviderHelper.sol";

import "@limitbreak/lb-amm-core/src/DataTypes.sol";
import "@limitbreak/lb-amm-core/src/interfaces/ILimitBreakAMM.sol";

import "@limitbreak/tm-core-lib/src/utils/cryptography/EfficientHash.sol";
import "@limitbreak/tm-core-lib/src/utils/misc/StaticDelegateCall.sol";
import "@limitbreak/tm-core-lib/src/licenses/LicenseRef-PolyForm-Strict-1.0.0.sol";

/**
 * @title  SingleProviderPoolType
 * @author Limit Break, Inc.
 * @notice Single Provider Pool Type is a pool type for LimitBreakAMM in which all liquidity is owned
 *         by a single provider and the price for each swap is provided by a hook that implements
 *         `ISingleProviderPoolHook`. This pool type allows for highly customizable pools that can
 *         change pricing in response to who the executor of the swap is or price feeds from an oracle.
 *
 * @dev    Handles creation, liquidity management, swaps, and fee collection for single-provider pools.
 *         Designed for pools with a single liquidity provider and deterministic pool IDs.
 */
contract SingleProviderPoolType is ISingleProviderPoolType, StaticDelegateCall {

    /// @dev The address of the AMM contract that manages this pool.
    address private immutable AMM;

    /// @dev Mapping of pool identifiers to their state.
    mapping (bytes32 => SingleProviderPoolState) private pools;

    constructor(address _amm) {
        AMM = _amm;
    }

    /**
     * @dev Modifier to restrict access to only the AMM contract.
     * @dev Throws when the msg.sender is not the AMM address.
     */
    modifier onlyAMM() {
        if (msg.sender != AMM) {
            revert SingleProviderPool__OnlyAMM();
        }
        _;
    }

    /**
     * @notice Creates a new single-provider pool with the specified parameters.
     *
     * @dev    Throws when poolParams cannot be decoded as SingleProviderPoolCreationDetails.
     *
     * @dev    Decodes poolParams as SingleProviderPoolCreationDetails and generates a deterministic pool ID.
     *
     *         <h4>Postconditions</h4>
     *         1. The pool ID is generated and returned to the caller.
     *
     * @param  poolCreationDetails  Pool creation parameters (see SingleProviderPoolCreationDetails).
     * @return poolId               The unique identifier for the created pool.
     */
    function createPool(
        PoolCreationDetails calldata poolCreationDetails
    ) external onlyAMM returns (bytes32 poolId) {
        SingleProviderPoolCreationDetails memory singleProviderPoolDetails = abi.decode(poolCreationDetails.poolParams, (SingleProviderPoolCreationDetails));

        if (poolCreationDetails.poolHook == address(0)) revert SingleProviderPool__NoPoolHookProvided();

        poolId = _generatePoolId(poolCreationDetails, singleProviderPoolDetails);

        pools[poolId].lastSqrtPriceX96 = singleProviderPoolDetails.sqrtPriceRatioX96;
    }

    /**
     * @notice Computes the deterministic pool ID that would be generated for given parameters.
     *
     * @dev    Throws when poolParams cannot be decoded as SingleProviderPoolCreationDetails.
     *
     * @param  poolCreationDetails  Pool creation parameters (see SingleProviderPoolCreationDetails).
     * @return poolId               Deterministic identifier that would be generated for these parameters.
     */
    function computePoolId(
        PoolCreationDetails calldata poolCreationDetails
    ) external view returns (bytes32 poolId) {
        SingleProviderPoolCreationDetails memory singleProviderPoolDetails = abi.decode(poolCreationDetails.poolParams, (SingleProviderPoolCreationDetails));

        poolId = _generatePoolId(poolCreationDetails, singleProviderPoolDetails);
    }

    /**
     * @dev    Generates a deterministic pool ID by hashing and bit-packing all relevant pool parameters.
     *
     *         Combines the pool type address, fee, salt, token addresses, and hook address into a unique bytes32 value.
     *         Applies a mask and bit shifts to ensure uniqueness and compatibility with the Limit Break AMM pool ID scheme.
     *
     * @param  poolCreationDetails         Pool creation parameters (see PoolCreationDetails).
     * @param  singleProviderPoolDetails   Decoded single-provider pool parameters (see SingleProviderPoolCreationDetails).
     * @return poolId                      Deterministic pool identifier for the given parameters.
     */
    function _generatePoolId(
        PoolCreationDetails calldata poolCreationDetails,
        SingleProviderPoolCreationDetails memory singleProviderPoolDetails
    ) internal view returns (bytes32 poolId) {
        poolId = EfficientHash.efficientHash(
            bytes32(uint256(uint160(address(this)))),
            bytes32(uint256(poolCreationDetails.fee)),
            singleProviderPoolDetails.salt,
            bytes32(uint256(uint160(poolCreationDetails.token0))),
            bytes32(uint256(uint160(poolCreationDetails.token1))),
            bytes32(uint256(uint160(poolCreationDetails.poolHook)))
        ) & POOL_HASH_MASK;

        poolId = poolId | 
            bytes32((uint256(uint160(address(this))) << POOL_ID_TYPE_ADDRESS_SHIFT)) |
            bytes32(uint256(poolCreationDetails.fee) << POOL_ID_FEE_SHIFT);
    }

    /**
     * @notice Collects accrued fees from a single-provider pool.
     *
     * @dev    Throws when the caller is not the allowed liquidity provider for the pool.
     *         Throws when the pool does not exist or the poolHook does not implement getPoolLiquidityProvider.
     *
     *         Returns collected amounts for AMM to handle actual token transfers.
     *
     *         <h4>Postconditions</h4>
     *         1. The fees are returned to the caller.
     *
     * @param  poolId              Pool identifier for fee collection.
     * @param  provider            Address of the liquidity provider.
     * @return positionId          Deterministic position identifier (equals poolId).
     * @return fees0               Collected fees in token0.
     * @return fees1               Collected fees in token1.
     */
    function collectFees(
        bytes32 poolId,
        address provider,
        bytes32,
        bytes calldata
    ) external view onlyAMM returns (
        bytes32 positionId,
        uint256 fees0,
        uint256 fees1
    ) {
        positionId = poolId;

        PoolState memory poolState = ILimitBreakAMM(AMM).getPoolState(poolId);
        address allowedProvider = ISingleProviderPoolHook(poolState.poolHook).getPoolLiquidityProvider(poolId);
        if (provider != allowedProvider) {
            revert SingleProviderPool__NotAllowedProvider();
        }

        fees0 = poolState.feeBalance0;
        fees1 = poolState.feeBalance1;
    }

    /**
     * @notice Adds liquidity to a single-provider pool.
     *
     * @dev    Throws when the caller is not the allowed liquidity provider for the pool.
     * @dev    Throws when poolParams cannot be decoded as SingleProviderLiquidityModificationParams.
     * @dev    Throws when the pool does not exist or the poolHook does not implement getPoolLiquidityProvider.
     *
     *         Decodes poolParams as SingleProviderLiquidityModificationParams.
     *
     *         <h4>Postconditions</h4>
     *         1. The deposit amounts and fees are returned to the caller.
     *
     * @param  poolId              Pool identifier for liquidity addition.
     * @param  provider            Address of the liquidity provider.
     * @param  poolParams          Encoded SingleProviderLiquidityModificationParams.
     * @return positionId          Deterministic position identifier.
     * @return deposit0            Amount of token0 to deposit.
     * @return deposit1            Amount of token1 to deposit.
     * @return fees0               Accrued fees in token0 collected during operation.
     * @return fees1               Accrued fees in token1 collected during operation.
     */
    function addLiquidity(
        bytes32 poolId,
        address provider,
        bytes32,
        bytes calldata poolParams
    ) external view onlyAMM returns (
        bytes32 positionId,
        uint256 deposit0,
        uint256 deposit1,
        uint256 fees0,
        uint256 fees1
    ) {
        SingleProviderLiquidityModificationParams memory liquidityParams = abi.decode(poolParams, (SingleProviderLiquidityModificationParams));
        positionId = poolId;

        PoolState memory poolState = ILimitBreakAMM(AMM).getPoolState(poolId);
        address allowedProvider = ISingleProviderPoolHook(poolState.poolHook).getPoolLiquidityProvider(poolId);
        if (provider != allowedProvider) {
            revert SingleProviderPool__NotAllowedProvider();
        }

        deposit0 = liquidityParams.amount0;
        deposit1 = liquidityParams.amount1;
        fees0 = poolState.feeBalance0;
        fees1 = poolState.feeBalance1;
    }

    /**
     * @notice Removes liquidity from a single-provider pool.
     *
     * @dev    Throws when the caller is not the allowed liquidity provider for the pool.
     * @dev    Throws when withdrawal amount exceeds available reserves.
     * @dev    Throws when poolParams cannot be decoded as SingleProviderLiquidityModificationParams.
     * @dev    Throws when the pool does not exist or the poolHook does not implement getPoolLiquidityProvider.
     *
     *         <h4>Postconditions</h4>
     *         1. The withdraw amounts and fees are returned to the caller.
     *
     * @param  poolId              Pool identifier for liquidity removal.
     * @param  provider            Address of the liquidity provider.
     * @param  poolParams          Encoded SingleProviderLiquidityModificationParams.
     * @return positionId          Deterministic position identifier.
     * @return withdraw0           Amount of token0 to withdraw.
     * @return withdraw1           Amount of token1 to withdraw.
     * @return fees0               Accrued fees in token0 collected during operation.
     * @return fees1               Accrued fees in token1 collected during operation.
     */
    function removeLiquidity(
        bytes32 poolId,
        address provider,
        bytes32,
        bytes calldata poolParams
    ) external view onlyAMM returns (
        bytes32 positionId,
        uint256 withdraw0,
        uint256 withdraw1,
        uint256 fees0,
        uint256 fees1
    ) {
        SingleProviderLiquidityModificationParams memory liquidityParams = abi.decode(poolParams, (SingleProviderLiquidityModificationParams));
        positionId = poolId;

        PoolState memory poolState = ILimitBreakAMM(AMM).getPoolState(poolId);
        address allowedProvider = ISingleProviderPoolHook(poolState.poolHook).getPoolLiquidityProvider(poolId);
        if (provider != allowedProvider) {
            revert SingleProviderPool__NotAllowedProvider();
        }

        if (liquidityParams.amount0 > poolState.reserve0 || liquidityParams.amount1 > poolState.reserve1) {
            revert SingleProviderPool__InsufficientReserves();
        }

        withdraw0 = liquidityParams.amount0;
        withdraw1 = liquidityParams.amount1;
        fees0 = poolState.feeBalance0;
        fees1 = poolState.feeBalance1;
    }

    /**
     * @notice Executes an input-based swap consuming up to the specified input for the calculated output.
     *
     * @dev    Throws when poolFeeBPS > MAX_BPS.
     * @dev    Throws when protocolFeeBPS > MAX_BPS.
     * @dev    Throws when the pool does not exist or the poolHook does not implement getPoolPriceForSwap.
     * @dev    Throws when output amount exceeds available reserves.
     * 
     *         <h4>Postconditions</h4>
     *         1. The pool's price cache is updated to the new value based on the pool hook's price logic.
     *         2. The required input amount, pool fees, and protocol fees are returned to the caller.
     *         3. A SingleProviderPoolSwapDetails event is emitted with the pool ID, execution price, and liquidity reserve.
     *
     * @param  poolId              Pool identifier for swap execution.
     * @param  zeroForOne          Swap direction: true for token0→token1, false for token1→token0.
     * @param  amountIn            Input amount to consume during swap.
     * @param  poolFeeBPS          Pool fee rate in basis points.
     * @param  protocolFeeBPS      Protocol fee rate in basis points.
     * @param  swapExtraData       Encoded parameters for price hook.
     * 
     * @return actualAmountIn      Input amount adjusted for partial fill.
     * @return amountOut           Output amount received from the swap.
     * @return feeOfAmountIn       Total fees charged on the input amount.
     * @return protocolFees        Protocol fees collected during the swap.
     */
    function swapByInput(
        SwapContext calldata context,
        bytes32 poolId,
        bool zeroForOne,
        uint256 amountIn,
        uint256 poolFeeBPS,
        uint256 protocolFeeBPS,
        bytes calldata swapExtraData
    ) external onlyAMM returns (
        uint256 actualAmountIn,
        uint256 amountOut,
        uint256 feeOfAmountIn,
        uint256 protocolFees
    ) {
        if (poolFeeBPS > MAX_BPS || protocolFeeBPS > MAX_BPS) {
            revert SingleProviderPool__InvalidFeeBPS();
        }

        ISingleProviderPoolHook.HookPoolPriceParams memory priceParams;
        priceParams.inputSwap = true;
        priceParams.poolId = poolId;
        priceParams.amount = amountIn;

        SingleProviderSwapCache memory swapCache;
        swapCache.zeroForOne = zeroForOne;
        swapCache.amountIn = amountIn;
        swapCache.protocolFeeBPS = uint16(protocolFeeBPS);

        {
            PoolState memory poolState = ILimitBreakAMM(AMM).getPoolState(poolId);
            swapCache.poolHook = poolState.poolHook;
            (
                priceParams.tokenIn,
                priceParams.tokenOut,
                swapCache.reserveOut
            ) = zeroForOne ? 
                (poolState.token0, poolState.token1, poolState.reserve1) : 
                (poolState.token1, poolState.token0, poolState.reserve0);
        }

        swapCache.sqrtPriceCurrentX96 = ISingleProviderPoolHook(swapCache.poolHook).getPoolPriceForSwap(
            context,
            priceParams,
            swapExtraData
        );
        if (swapCache.sqrtPriceCurrentX96 < MIN_SQRT_RATIO || swapCache.sqrtPriceCurrentX96 >= MAX_SQRT_RATIO) {
            revert SingleProviderPool__InvalidPrice();
        }
        pools[poolId].lastSqrtPriceX96 = swapCache.sqrtPriceCurrentX96;

        SingleProviderHelper.swapByInput(swapCache, uint16(poolFeeBPS));

        actualAmountIn = swapCache.amountIn;
        amountOut = swapCache.amountOut;
        feeOfAmountIn = swapCache.feeAmount;
        protocolFees = swapCache.protocolFee;

        emit SingleProviderPoolSwapDetails(poolId, swapCache.sqrtPriceCurrentX96, swapCache.reserveOut);
    }

    /**
     * @notice Executes an output-based swap consuming the required input amount for the specified output.
     *
     * @dev    Throws when poolFeeBPS >= MAX_BPS.
     * @dev    Throws when protocolFeeBPS > MAX_BPS.
     * @dev    Throws when the pool does not exist or the poolHook does not implement getPoolPriceForSwap.
     * @dev    Throws when output amount exceeds available reserves.
     *
     *         <h4>Postconditions</h4>
     *         1. The pool's price cache is updated to the new value based on the pool hook's price logic.
     *         2. The required input amount, pool fees, and protocol fees are returned to the caller.
     *         3. A SingleProviderPoolSwapDetails event is emitted with the pool ID, new price, and liquidity reserve.
     *
     * @param  poolId              Pool identifier for swap execution.
     * @param  zeroForOne          Swap direction: true for token0→token1, false for token1→token0.
     * @param  amountOut           Output amount to produce during swap.
     * @param  poolFeeBPS          Pool fee rate in basis points.
     * @param  protocolFeeBPS      Protocol fee rate in basis points.
     * @param  swapExtraData       Encoded parameters for price hook.
     * 
     * @return actualAmountOut     Output amount adjusted for partial fill.
     * @return amountIn            Input amount consumed during the swap.
     * @return feeOfAmountIn       External fees charged on the input amount.
     * @return protocolFees        Protocol fees collected during the swap.
     */
    function swapByOutput(
        SwapContext calldata context,
        bytes32 poolId,
        bool zeroForOne,
        uint256 amountOut,
        uint256 poolFeeBPS,
        uint256 protocolFeeBPS,
        bytes calldata swapExtraData
    ) external onlyAMM returns (
        uint256 actualAmountOut,
        uint256 amountIn,
        uint256 feeOfAmountIn,
        uint256 protocolFees
    ) {
        if (poolFeeBPS >= MAX_BPS || protocolFeeBPS > MAX_BPS) {
            revert SingleProviderPool__InvalidFeeBPS();
        }

        ISingleProviderPoolHook.HookPoolPriceParams memory priceParams;
        priceParams.inputSwap = false;
        priceParams.poolId = poolId;
        priceParams.amount = amountOut;

        SingleProviderSwapCache memory swapCache;
        swapCache.zeroForOne = zeroForOne;
        swapCache.amountOut = amountOut;
        swapCache.protocolFeeBPS = uint16(protocolFeeBPS);

        {
            PoolState memory poolState = ILimitBreakAMM(AMM).getPoolState(priceParams.poolId);
            swapCache.poolHook = poolState.poolHook;
            (
                priceParams.tokenIn,
                priceParams.tokenOut,
                swapCache.reserveOut
            ) = zeroForOne ? 
                (poolState.token0, poolState.token1, poolState.reserve1) : 
                (poolState.token1, poolState.token0, poolState.reserve0);
        }

        swapCache.sqrtPriceCurrentX96 = ISingleProviderPoolHook(swapCache.poolHook).getPoolPriceForSwap(
            context,
            priceParams,
            swapExtraData
        );
        if (swapCache.sqrtPriceCurrentX96 < MIN_SQRT_RATIO || swapCache.sqrtPriceCurrentX96 >= MAX_SQRT_RATIO) {
            revert SingleProviderPool__InvalidPrice();
        }
        pools[poolId].lastSqrtPriceX96 = swapCache.sqrtPriceCurrentX96;

        SingleProviderHelper.swapByOutput(swapCache, uint16(poolFeeBPS));

        actualAmountOut = swapCache.amountOut;
        amountIn = swapCache.amountIn;
        feeOfAmountIn = swapCache.feeAmount;
        protocolFees = swapCache.protocolFee;

        emit SingleProviderPoolSwapDetails(poolId, swapCache.sqrtPriceCurrentX96, swapCache.reserveOut);
    }

    /**
     * @notice Returns the current square root price for a specific pool.
     *
     * @dev    View function that retrieves the current sqrtPriceX96 from pool state.
     *         Returns 0 if pool does not exist.
     *
     * @param  poolId              Pool identifier to query.
     * @return sqrtPriceX96        Current square root price in Q64.96 fixed-point format.
     */
    function getCurrentPriceX96(
        address,
        bytes32 poolId
    ) external view returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = pools[poolId].lastSqrtPriceX96;
    }

    /**
     * @notice  Returns the manifest URI for the pool type to provide app integrations with
     *          information necessary to process transactions that utilize the pool type.
     * 
     * @dev     Hook developers **MUST** emit a `PoolTypeManifestUriUpdated` event if the URI
     *          changes.
     * 
     * @return  manifestUri  The URI for the hook manifest data. 
     */
    function poolTypeManifestUri() external pure returns(string memory manifestUri) {
        manifestUri = ""; //TODO: Before final deploy, create permalink for SingleProviderPoolType manifest
    }
}