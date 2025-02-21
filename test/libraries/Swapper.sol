// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {StdCheats} from "forge-std/StdCheats.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Swapper is StdCheats, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20Metadata;

    function movePoolPrice(
        INonfungiblePositionManager positionManager,
        address token0,
        address token1,
        uint24 fee,
        uint160 targetSqrtPriceX96
    ) public {
        IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(positionManager.factory()).getPool(token0, token1, fee));

        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        if (sqrtPriceX96 > targetSqrtPriceX96) {
            pool.swap(msg.sender, true, type(int256).max, targetSqrtPriceX96, abi.encode(token0, token1));
        } else {
            pool.swap(msg.sender, false, type(int256).max, targetSqrtPriceX96, abi.encode(token1, token0));
        }
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(amount0Delta > 0 || amount1Delta > 0);

        (address tokenIn, address tokenOut) = abi.decode(data, (address, address));
        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));

        if (isExactInput) {
            deal(tokenIn, address(this), amountToPay);
            IERC20Metadata(tokenIn).safeTransfer(msg.sender, amountToPay);
        } else {
            deal(tokenOut, address(this), amountToPay);
            IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountToPay);
        }
    }
}
