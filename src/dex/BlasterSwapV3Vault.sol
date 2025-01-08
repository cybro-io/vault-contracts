// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseDexVault, BaseDexUniformVault, TickMath} from "./BaseDexVault.sol";
import {IBlasterswapV3SwapCallback} from "../interfaces/blaster/IBlasterswapV3SwapCallback.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseVault} from "../BaseVault.sol";

/**
 * @title BlasterSwapV3Vault
 * @notice A vault for managing liquidity positions on BlasterSwap V3 pools
 */
contract BlasterSwapV3Vault is BaseDexVault, IBlasterswapV3SwapCallback {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    /// @notice The BlasterSwap V3 pool associated with this vault
    IUniswapV3Pool public immutable pool;

    /// @notice The fee tier of the pool
    uint24 public immutable fee;

    /// @notice Address of the BlasterSwap V3 position manager contract
    INonfungiblePositionManager public immutable positionManager;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address payable _positionManager,
        address _token0,
        address _token1,
        uint24 _fee,
        IERC20Metadata _asset,
        IFeeProvider _feeProvider,
        address _feeRecipient
    ) BaseDexVault(_token0, _token1, _asset, _feeProvider, _feeRecipient) {
        positionManager = INonfungiblePositionManager(_positionManager);
        fee = _fee;
        pool = IUniswapV3Pool(IUniswapV3Factory(positionManager.factory()).getPool(_token0, _token1, fee));
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the vault with the specified admin, token name, and symbol
     * @param admin The address of the admin to be set as the owner
     * @param manager The address of the manager
     * @param name The name of the ERC20 token representing vault shares
     * @param symbol The symbol of the ERC20 token representing vault shares
     */
    function initialize(address admin, address manager, string memory name, string memory symbol) public initializer {
        IERC20Metadata(token0).forceApprove(address(positionManager), type(uint256).max);
        IERC20Metadata(token1).forceApprove(address(positionManager), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseDexVault_init(admin, manager);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc BaseDexUniformVault
    function getCurrentSqrtPrice() public view override returns (uint256 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = pool.slot0();
        return uint256(sqrtPriceX96);
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view override returns (uint256) {
        uint256 sqrtPrice = getCurrentSqrtPrice();
        return isToken0
            ? IERC20Metadata(token0).balanceOf(address(pool))
                + Math.mulDiv(IERC20Metadata(token1).balanceOf(address(pool)), 2 ** 192, sqrtPrice)
            : IERC20Metadata(token1).balanceOf(address(pool))
                + Math.mulDiv(IERC20Metadata(token0).balanceOf(address(pool)), sqrtPrice, 2 ** 192);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @inheritdoc BaseDexVault
    function _getTokenLiquidity(uint256 tokenId) internal view virtual override returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = positionManager.positions(tokenId);
    }

    /// @inheritdoc BaseDexVault
    function _getTokensOwed(uint256 tokenId)
        internal
        view
        virtual
        override
        returns (uint128 amount0, uint128 amount1)
    {
        (,,,,,,,,,, amount0, amount1) = positionManager.positions(tokenId);
    }

    /// @inheritdoc BaseDexVault
    function _updateTicks() internal override {
        // Calculate upper and lower ticks based on the pool's tick spacing and maximum tick values
        int24 tickUpper_ = TickMath.MAX_TICK - TickMath.MAX_TICK % pool.tickSpacing();
        _setTicks(-tickUpper_, tickUpper_);
    }

    /// @inheritdoc BaseDexUniformVault
    function _swap(bool zeroForOne, uint256 amount) internal override returns (uint256) {
        // Execute the swap and capture the output amount
        (int256 amount0, int256 amount1) = pool.swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(token0, token1)
        );

        // Return the output amount (convert from negative if needed)
        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc BaseDexVault
    function _mintPosition(uint256 amount0, uint256 amount1)
        internal
        override
        returns (uint256 tokenId, uint256 amount0Used, uint256 amount1Used)
    {
        // Mint a new liquidity position using the specified amounts of token0 and token1
        (tokenId,, amount0Used, amount1Used) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower(),
                tickUpper: tickUpper(),
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
        returns (uint256 amount0Used, uint256 amount1Used)
    {
        // Increase liquidity for the existing position using additional token0 and token1
        (, amount0Used, amount1Used) = positionManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId(),
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
        // Decrease liquidity for the current position and return the received token amounts
        (amount0, amount1) = positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: positionTokenId(),
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
        // Collect earned fees from the liquidity position
        (amount0, amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId(),
                recipient: address(this),
                amount0Max: amount0Max,
                amount1Max: amount1Max
            })
        );
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    /// @inheritdoc IBlasterswapV3SwapCallback
    function blasterswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data)
        external
        override
    {
        // Ensure the callback is being called by the correct pool
        require(amount0Delta > 0 || amount1Delta > 0);
        require(msg.sender == address(pool), "BlasterSwapV3Vault: invalid swap callback caller");

        (address tokenIn, address tokenOut) = abi.decode(data, (address, address));
        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0 ? (tokenIn < tokenOut, uint256(amount0Delta)) : (tokenOut < tokenIn, uint256(amount1Delta));

        // Transfer the required amount back to the pool
        if (isExactInput) {
            IERC20Metadata(tokenIn).safeTransfer(msg.sender, amountToPay);
        } else {
            IERC20Metadata(tokenOut).safeTransfer(msg.sender, amountToPay);
        }
    }
}
