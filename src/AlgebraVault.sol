// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseDexVault, TickMath} from "./BaseDexVault.sol";
import {IAlgebraFactory} from "./interfaces/algebra/IAlgebraFactory.sol";
import {IAlgebraPool} from "./interfaces/algebra/IAlgebraPool.sol";
import {IAlgebraSwapCallback} from "./interfaces/algebra/IAlgebraSwapCallback.sol";
import {IAlgebraMintCallback} from "./interfaces/algebra/IAlgebraMintCallback.sol";
import {INonfungiblePositionManager} from "./interfaces/algebra/INonfungiblePositionManager.sol";

contract AlgebraVault is BaseDexVault, IAlgebraSwapCallback {
    IAlgebraPool public immutable pool;

    constructor(address _positionManager, address _token0, address _token1)
        BaseDexVault(_positionManager, _token0, _token1)
    {
        pool = IAlgebraPool(IAlgebraFactory(factory).poolByPair(_token0, _token1));
        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __BaseDexVault_init(admin);
    }

    function _getCurrentSqrtPrice() internal view override returns (uint160) {
        (uint160 sqrtPriceX96,,,,,,,) = pool.globalState();
        return sqrtPriceX96;
    }

    function _swap(bool zeroForOne, uint256 amount) internal override returns (uint256) {
        (int256 amount0, int256 amount1) = pool.swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(token0, token1)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    function _mintPosition(uint256 amount0, uint256 amount1) internal override returns (uint256 tokenId) {
        (tokenId,,,) = INonfungiblePositionManager(positionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );
    }

    function _increaseLiquidity(uint256 amount0, uint256 amount1) internal override returns (uint128 liquidity) {
        (liquidity,,) = INonfungiblePositionManager(positionManager).increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max
            })
        );
    }

    function _decreaseLiquidity(uint128 liquidity) internal override returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = INonfungiblePositionManager(positionManager).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: positionTokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max
            })
        );
    }

    function _collect(uint128 amount0Max, uint128 amount1Max)
        internal
        override
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = INonfungiblePositionManager(positionManager).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: address(this),
                amount0Max: amount0Max,
                amount1Max: amount1Max
            })
        );
    }

    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        _swapCallback(amount0Delta, amount1Delta, data);
    }
}
