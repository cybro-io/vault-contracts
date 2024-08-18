// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseDexVault, TickMath} from "./BaseDexVault.sol";
import {IAlgebraFactory} from "./interfaces/algebra/IAlgebraFactory.sol";
import {IAlgebraPool} from "./interfaces/algebra/IAlgebraPool.sol";
import {IAlgebraSwapCallback} from "./interfaces/algebra/IAlgebraSwapCallback.sol";
import {INonfungiblePositionManager} from "./interfaces/algebra/INonfungiblePositionManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AlgebraVault - A vault that interacts with Algebra-based V1 pools for managing liquidity positions
/// @notice This contract extends BaseDexVault to manage liquidity positions specifically for Algebra pools
contract AlgebraVault is BaseDexVault, IAlgebraSwapCallback {
    using SafeERC20 for IERC20Metadata;

    IAlgebraPool public immutable pool;

    /// @notice Address of the position manager contract
    INonfungiblePositionManager public immutable positionManager;

    constructor(address payable _positionManager, address _token0, address _token1) BaseDexVault(_token0, _token1) {
        positionManager = INonfungiblePositionManager(_positionManager);
        pool = IAlgebraPool(IAlgebraFactory(positionManager.factory()).poolByPair(_token0, _token1));
        _disableInitializers();
    }

    /// @notice Initializes the vault
    /// @param admin The address of the admin to be set as the owner
    /// @param name The name of the ERC20 token representing vault shares
    /// @param symbol The symbol of the ERC20 token representing vault shares
    function initialize(address admin, string memory name, string memory symbol) public initializer {
        IERC20Metadata(token0).approve(address(positionManager), type(uint256).max);
        IERC20Metadata(token1).approve(address(positionManager), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseDexVault_init(admin);
    }

    /// @inheritdoc BaseDexVault
    function _getTokenLiquidity() internal view virtual override returns (uint128 liquidity) {
        (,,,,,, liquidity,,,,) = positionManager.positions(positionTokenId);
    }

    /// @inheritdoc BaseDexVault
    function _getTokensOwed() internal virtual override returns (uint128 amount0, uint128 amount1) {
        (,,,,,,,,, amount0, amount1) = positionManager.positions(positionTokenId);
    }

    /// @inheritdoc BaseDexVault
    function getCurrentSqrtPrice() public view override returns (uint160) {
        (uint160 sqrtPriceX96,,,,,) = pool.globalState();
        return sqrtPriceX96;
    }

    /// @inheritdoc BaseDexVault
    function _updateTicks() internal virtual override {
        tickUpper = TickMath.MAX_TICK - TickMath.MAX_TICK % pool.tickSpacing();
        tickLower = -tickUpper;
    }

    /// @inheritdoc BaseDexVault
    function _swap(bool zeroForOne, uint256 amount) internal override returns (uint256) {
        // Perform a token swap on the Algebra pool and return the amount received
        (int256 amount0, int256 amount1) = pool.swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            zeroForOne ? abi.encode(token0, token1) : abi.encode(token1, token0)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc BaseDexVault
    function _mintPosition(uint256 amount0, uint256 amount1)
        internal
        override
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        (tokenId, liquidity, amount0Used, amount1Used) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
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

    /// @inheritdoc BaseDexVault
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

    /// @inheritdoc BaseDexVault
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

    /// @inheritdoc BaseDexVault
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

    /// @notice Callback function for swaps
    /// @param amount0Delta The change in token0 amount
    /// @param amount1Delta The change in token1 amount
    /// @param data Additional data needed to process the callback
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Validate that the swap callback was called by the correct pool
        require(amount0Delta > 0 || amount1Delta > 0);
        (address tokenIn, address tokenOut) = abi.decode(data, (address, address));
        require(address(pool) == msg.sender, "AlgebraVault: invalid swap callback caller");

        // Handle the payment for the swap based on the direction of the swap
        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));
        if (isExactInput) {
            IERC20Metadata(tokenIn).safeTransfer(msg.sender, amountToPay);
        } else {
            IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountToPay);
        }
    }
}
