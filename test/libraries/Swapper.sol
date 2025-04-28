// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.29;

import {StdCheats} from "forge-std/StdCheats.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAlgebraSwapCallback} from "../../src/interfaces/algebra/IAlgebraSwapCallback.sol";
import {IBlasterswapV3SwapCallback} from "../../src/interfaces/blaster/IBlasterswapV3SwapCallback.sol";
import {INonfungiblePositionManager as IPositionManagerAlgebra} from
    "../../src/interfaces/algebra/INonfungiblePositionManager.sol";
import {IAlgebraPool} from "../../src/interfaces/algebra/IAlgebraPool.sol";
import {IAlgebraFactory} from "../../src/interfaces/algebra/IAlgebraFactory.sol";
import {DeployUtils} from "../DeployUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {IBlasterswapV2Pair} from "../../src/interfaces/blaster/IBlasterswapV2Pair.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAlgebraPool as IAlgebraPoolV1_9} from "../../src/interfaces/algebra/IAlgebraPoolV1_9.sol";

enum VaultType {
    UniV3,
    AlgebraV1,
    BlasterV2,
    AlgebraV1_9
}

contract Swapper is IUniswapV3SwapCallback, IAlgebraSwapCallback, IBlasterswapV3SwapCallback, DeployUtils {
    using SafeERC20 for IERC20Metadata;

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

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

    function _movePoolPriceAlgebra(IAlgebraPool pool, address token0, address token1, uint160 targetSqrtPriceX96)
        internal
    {
        (uint160 sqrtPriceX96,,,,,) = pool.globalState();

        if (sqrtPriceX96 > targetSqrtPriceX96) {
            pool.swap(msg.sender, true, type(int256).max, targetSqrtPriceX96, abi.encode(token0, token1));
        } else {
            pool.swap(msg.sender, false, type(int256).max, targetSqrtPriceX96, abi.encode(token1, token0));
        }
    }

    function _movePoolPriceUniV3(IUniswapV3Pool pool, address token0, address token1, uint160 targetSqrtPriceX96)
        internal
    {
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();

        if (sqrtPriceX96 > targetSqrtPriceX96) {
            pool.swap(msg.sender, true, type(int256).max, targetSqrtPriceX96, abi.encode(token0, token1));
        } else {
            pool.swap(msg.sender, false, type(int256).max, targetSqrtPriceX96, abi.encode(token1, token0));
        }
    }

    function _movePoolPriceBlasterV2(
        IBlasterswapV2Pair pool,
        address token0,
        address token1,
        uint160 targetSqrtPriceX96
    ) internal {
        (uint112 reserve0, uint112 reserve1,) = pool.getReserves();
        uint256 sqrtK = Math.sqrt(uint256(reserve0) * uint256(reserve1));

        uint256 r0Target = (sqrtK * (2 ** 96)) / uint256(targetSqrtPriceX96);
        uint256 r1Target = (sqrtK * uint256(targetSqrtPriceX96)) / (2 ** 96);

        if (r1Target > reserve1) {
            uint256 amount1In = r1Target - reserve1;
            uint256 amount0Out =
                reserve0 - ((uint256(reserve0) * uint256(reserve1) * 1000) / ((uint256(reserve1) + amount1In) * 997));

            dealTokens(IERC20Metadata(token1), address(pool), amount1In);
            IERC20Metadata(token1).forceApprove(address(pool), amount1In);

            pool.swap(amount0Out, 0, address(this), new bytes(0));
        } else if (r0Target > reserve0) {
            uint256 amount0In = r0Target - reserve0;
            uint256 amount1Out =
                reserve1 - ((uint256(reserve0) * uint256(reserve1) * 1000) / ((uint256(reserve0) + amount0In) * 997));

            dealTokens(IERC20Metadata(token0), address(pool), amount0In);
            IERC20Metadata(token0).forceApprove(address(pool), amount0In);

            pool.swap(0, amount1Out, address(this), new bytes(0));
        }
    }

    function _movePoolPriceAlgebraV1_9(
        IAlgebraPoolV1_9 pool,
        address token0,
        address token1,
        uint160 targetSqrtPriceX96
    ) internal {
        (uint160 sqrtPriceX96,,,,,,,) = pool.globalState();
        if (sqrtPriceX96 > targetSqrtPriceX96) {
            pool.swap(msg.sender, true, type(int256).max, targetSqrtPriceX96, abi.encode(token0, token1));
        } else {
            pool.swap(msg.sender, false, type(int256).max, targetSqrtPriceX96, abi.encode(token1, token0));
        }
    }

    function movePoolPrice(
        address pool,
        address token0,
        address token1,
        uint160 targetSqrtPriceX96,
        VaultType vaultType_
    ) public {
        if (vaultType_ == VaultType.AlgebraV1) {
            _movePoolPriceAlgebra(IAlgebraPool(pool), token0, token1, targetSqrtPriceX96);
        } else if (vaultType_ == VaultType.UniV3) {
            _movePoolPriceUniV3(IUniswapV3Pool(pool), token0, token1, targetSqrtPriceX96);
        } else if (vaultType_ == VaultType.BlasterV2) {
            _movePoolPriceBlasterV2(IBlasterswapV2Pair(pool), token0, token1, targetSqrtPriceX96);
        } else if (vaultType_ == VaultType.AlgebraV1_9) {
            _movePoolPriceAlgebraV1_9(IAlgebraPoolV1_9(pool), token0, token1, targetSqrtPriceX96);
        }
    }

    function _callback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) internal {
        require(amount0Delta > 0 || amount1Delta > 0);

        (address tokenIn, address tokenOut) = abi.decode(data, (address, address));
        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));

        if (isExactInput) {
            dealTokens(IERC20Metadata(tokenIn), address(this), amountToPay);
            IERC20Metadata(tokenIn).safeTransfer(msg.sender, amountToPay);
        } else {
            dealTokens(IERC20Metadata(tokenOut), address(this), amountToPay);
            IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountToPay);
        }
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        _callback(amount0Delta, amount1Delta, data);
    }

    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        _callback(amount0Delta, amount1Delta, data);
    }

    function blasterswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external
        override
    {
        _callback(amount0Delta, amount1Delta, data);
    }
}
