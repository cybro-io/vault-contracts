// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseDexVault, TickMath} from "./BaseDexVault.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract UniswapVault is BaseDexVault, IUniswapV3SwapCallback {
    IUniswapV3Pool public immutable pool;
    uint24 public immutable fee;

    constructor(address _positionManager, address _token0, address _token1, uint24 _fee)
        BaseDexVault(_positionManager, _token0, _token1)
    {
        fee = _fee;
        pool = IUniswapV3Pool(IUniswapV3Factory(factory).getPool(_token0, _token1, _fee));
        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __BaseDexVault_init(admin);
    }

    function _getCurrentSqrtPrice() internal view override returns (uint160) {
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        return sqrtPriceX96;
    }

    function _swap(bool zeroForOne, uint256 amount) internal override returns (uint256) {
        (int256 amount0, int256 amount1) = pool.swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(token0, token1, fee)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    function _mintPosition(uint256 amount0, uint256 amount1) internal override returns (uint256 tokenId) {
        (tokenId,,,) = INonfungiblePositionManager(positionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
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

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        _swapCallback(amount0Delta, amount1Delta, _data);
    }
}
