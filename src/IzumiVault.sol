// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseDexVault, BaseDexUniformVault, TickMath} from "./BaseDexVault.sol";
import {IiZiSwapFactory} from "./interfaces/izumi/IiZiSwapFactory.sol";
import {IiZiSwapPool} from "./interfaces/izumi/IiZiSwapPool.sol";
import {IiZiSwapCallback} from "./interfaces/izumi/IiZiSwapCallback.sol";
import {ILiquidityManager} from "./interfaces/izumi/ILiquidityManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";

/// @title IzumiVault - A vault that interacts with iZiSwap pools for managing liquidity positions
/// @notice This contract extends BaseDexVault to manage liquidity positions specifically for iZiSwap pools
contract IzumiVault is BaseDexVault, IiZiSwapCallback {
    using SafeERC20 for IERC20Metadata;

    /// @notice The pool associated with this vault
    IiZiSwapPool public immutable pool;

    /// @notice Address of the position manager contract
    ILiquidityManager public immutable positionManager;

    /// @notice The fee tier of the pool
    uint24 public immutable fee;

    /// @notice Constant used in calculating the range for liquidity management
    int24 constant HALF_MOST_PT = 400000;

    constructor(address payable _positionManager, address _token0, address _token1, uint24 _fee)
        BaseDexVault(_token0, _token1)
    {
        positionManager = ILiquidityManager(_positionManager);
        fee = _fee;
        pool = IiZiSwapPool(IiZiSwapFactory(positionManager.factory()).pool(_token0, _token1, fee));
        _disableInitializers();
    }

    /// @notice Initializes the vault
    /// @param admin The address of the admin to be set as the owner
    /// @param name The name of the ERC20 token representing vault shares
    /// @param symbol The symbol of the ERC20 token representing vault shares
    function initialize(address admin, string memory name, string memory symbol) public initializer {
        IERC20Metadata(token0).forceApprove(address(positionManager), type(uint256).max);
        IERC20Metadata(token1).forceApprove(address(positionManager), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseDexVault_init(admin);
    }

    /// @inheritdoc BaseDexVault
    function _getTokenLiquidity(uint256 tokenId) internal view virtual override returns (uint128 liquidity) {
        (,, liquidity,,,,,) = positionManager.liquidities(tokenId);
    }

    /// @inheritdoc BaseDexVault
    function _getTokensOwed() internal virtual override returns (uint128, uint128) {
        (,,,,, uint256 amount0, uint256 amount1,) = positionManager.liquidities(positionTokenId);
        return (uint128(amount0), uint128(amount1));
    }

    /// @inheritdoc BaseDexUniformVault
    function getCurrentSqrtPrice() public view override returns (uint160) {
        (uint160 sqrtPriceX96,,,,,,,) = pool.state();
        return sqrtPriceX96;
    }

    /// @inheritdoc BaseDexVault
    function _updateTicks() internal virtual override {
        (, int24 currPt,,,,,,) = pool.state();
        int24 rightMostPt = pool.rightMostPt();
        int24 leftMostPt = pool.leftMostPt();
        int24 pointDelta = pool.pointDelta();

        tickLower = int24(SignedMath.max(currPt - HALF_MOST_PT, leftMostPt));
        tickLower -= tickLower % pointDelta;

        tickUpper = int24(SignedMath.min(tickLower + HALF_MOST_PT * 2, rightMostPt));
        tickUpper -= tickUpper % pointDelta;
        if (tickUpper - tickLower == HALF_MOST_PT * 2) tickLower += pointDelta;
    }

    /// @inheritdoc BaseDexUniformVault
    function _swap(bool zeroForOne, uint256 amount) internal override returns (uint256) {
        uint256 amount0;
        uint256 amount1;
        if (zeroForOne) {
            (amount0, amount1) = pool.swapX2Y(address(this), uint128(amount), tickLower, abi.encode(token0, token1));
        } else {
            (amount0, amount1) = pool.swapY2X(address(this), uint128(amount), tickUpper, abi.encode(token1, token0));
        }

        return zeroForOne ? amount1 : amount0;
    }

    /// @inheritdoc BaseDexVault
    function _mintPosition(uint256 amount0, uint256 amount1)
        internal
        override
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used)
    {
        (tokenId, liquidity, amount0Used, amount1Used) = positionManager.mint(
            ILiquidityManager.MintParam({
                miner: address(this),
                tokenX: token0,
                tokenY: token1,
                fee: fee,
                pl: tickLower,
                pr: tickUpper,
                xLim: uint128(amount0),
                yLim: uint128(amount1),
                amountXMin: 0,
                amountYMin: 0,
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
        (liquidity, amount0Used, amount1Used) = positionManager.addLiquidity(
            ILiquidityManager.AddLiquidityParam({
                lid: positionTokenId,
                xLim: uint128(amount0),
                yLim: uint128(amount1),
                amountXMin: 0,
                amountYMin: 0,
                deadline: type(uint256).max
            })
        );
    }

    /// @inheritdoc BaseDexVault
    function _decreaseLiquidity(uint128 liquidity) internal override returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = positionManager.decLiquidity(positionTokenId, liquidity, 0, 0, type(uint256).max);
    }

    /// @inheritdoc BaseDexVault
    function _collect(uint128 amount0Max, uint128 amount1Max)
        internal
        override
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = positionManager.collect(address(this), positionTokenId, amount0Max, amount1Max);
    }

    /// @notice Callback function for swapY2X operation on the iZiSwap pool
    /// @param x The amount of tokenX received in the swap
    /// @param y The amount of tokenY received in the swap
    /// @param data The data passed in the swap call, used here to decode token addresses
    function swapY2XCallback(uint256 x, uint256 y, bytes calldata data) external override {
        require(x > 0 || y > 0, "IzumiVault: invalid swap amounts");
        require(address(pool) == msg.sender, "IzumiVault: invalid swap callback caller");
        (address tokenIn,) = abi.decode(data, (address, address));
        // Transfer the required amount of tokenIn back to the pool
        IERC20Metadata(tokenIn).safeTransfer(msg.sender, y);
    }

    /// @notice Callback function for swapX2Y operation on the iZiSwap pool
    /// @param x The amount of tokenX received in the swap
    /// @param y The amount of tokenY received in the swap
    /// @param data The data passed in the swap call, used here to decode token addresses
    function swapX2YCallback(uint256 x, uint256 y, bytes calldata data) external override {
        require(x > 0 || y > 0, "IzumiVault: invalid swap amounts");
        require(address(pool) == msg.sender, "IzumiVault: invalid swap callback caller");
        (address tokenIn,) = abi.decode(data, (address, address));
        // Transfer the required amount of tokenIn back to the pool
        IERC20Metadata(tokenIn).safeTransfer(msg.sender, x);
    }
}
