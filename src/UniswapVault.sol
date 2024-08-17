// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseDexVault, TickMath} from "./BaseDexVault.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {CallbackValidation} from "@uniswap/v3-periphery/contracts/libraries/CallbackValidation.sol";
import {PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniswapVault is BaseDexVault, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20Metadata;

    IUniswapV3Pool public immutable pool;
    uint24 public immutable fee;

    /// @notice Address of the position manager contract
    INonfungiblePositionManager public immutable positionManager;

    constructor(address payable _positionManager, address _token0, address _token1, uint24 _fee)
        BaseDexVault(_token0, _token1)
    {
        positionManager = INonfungiblePositionManager(_positionManager);
        fee = _fee;
        pool = IUniswapV3Pool(IUniswapV3Factory(positionManager.factory()).getPool(_token0, _token1, _fee));
        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol) public initializer {
        IERC20Metadata(token0).approve(address(positionManager), type(uint256).max);
        IERC20Metadata(token1).approve(address(positionManager), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseDexVault_init(admin);
    }

    function _getTokenLiquidity() internal view virtual override returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = positionManager.positions(positionTokenId);
    }

    function _getTokensOwed() internal virtual override returns (uint128 amount0, uint128 amount1) {
        (,,,,,,,,,, amount0, amount1) = positionManager.positions(positionTokenId);
    }

    function _getCurrentSqrtPrice() internal view override returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = pool.slot0();
    }

    function _updateTicks() internal override {
        tickUpper = TickMath.MAX_TICK - TickMath.MAX_TICK % pool.tickSpacing();
        tickLower = -tickUpper;
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

    function _mintPosition(uint256 amount0, uint256 amount1)
        internal
        override
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        (tokenId, liquidity, amount0Used, amount1Used) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );
    }

    function _increaseLiquidity(uint256 amount0, uint256 amount1)
        internal
        override
        returns (uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        (liquidity, amount0Used, amount1Used) = positionManager.increaseLiquidity(
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
        (amount0, amount1) = positionManager.decreaseLiquidity(
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
        (amount0, amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: address(this),
                amount0Max: amount0Max,
                amount1Max: amount1Max
            })
        );
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(amount0Delta > 0 || amount1Delta > 0);
        require(msg.sender == address(pool));

        (address tokenIn, address tokenOut) = abi.decode(data, (address, address));

        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));
        if (isExactInput) {
            IERC20Metadata(tokenIn).safeTransfer(msg.sender, amountToPay);
        } else {
            IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountToPay);
        }
    }
}
