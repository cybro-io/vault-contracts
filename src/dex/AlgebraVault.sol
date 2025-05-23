// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {BaseDexVault, BaseDexUniformVault, TickMath} from "./BaseDexVault.sol";
import {IAlgebraFactory} from "../interfaces/algebra/IAlgebraFactory.sol";
import {IAlgebraPool} from "../interfaces/algebra/IAlgebraPool.sol";
import {IAlgebraSwapCallback} from "../interfaces/algebra/IAlgebraSwapCallback.sol";
import {INonfungiblePositionManager} from "../interfaces/algebra/INonfungiblePositionManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseVault} from "../BaseVault.sol";
import {DexPriceCheck} from "../libraries/DexPriceCheck.sol";

/**
 * @title AlgebraVault
 * @notice This contract extends BaseDexVault to manage liquidity positions specifically for Algebra pools
 */
contract AlgebraVault is BaseDexVault, IAlgebraSwapCallback {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    IAlgebraPool public immutable pool;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice Address of the position manager contract
    INonfungiblePositionManager public immutable positionManager;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address payable _positionManager,
        address _token0,
        address _token1,
        IERC20Metadata _asset,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        address _oracleToken0,
        address _oracleToken1
    ) BaseDexVault(_token0, _token1, _asset, _feeProvider, _feeRecipient, _oracleToken0, _oracleToken1) {
        positionManager = INonfungiblePositionManager(_positionManager);
        pool = IAlgebraPool(IAlgebraFactory(positionManager.factory()).poolByPair(_token0, _token1));
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the vault
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
    function getCurrentSqrtPrice() public view override returns (uint256) {
        (uint160 sqrtPriceX96,,,,,) = pool.globalState();
        return uint256(sqrtPriceX96);
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view override returns (uint256) {
        uint256 sqrtPrice = getCurrentSqrtPrice();
        return isToken0
            ? IERC20Metadata(token0).balanceOf(address(pool))
                + Math.mulDiv(IERC20Metadata(token1).balanceOf(address(pool)), 2 ** 192, sqrtPrice * sqrtPrice)
            : IERC20Metadata(token1).balanceOf(address(pool))
                + Math.mulDiv(IERC20Metadata(token0).balanceOf(address(pool)), sqrtPrice * sqrtPrice, 2 ** 192);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @inheritdoc BaseDexUniformVault
    function _checkPriceManipulation() internal view override {
        DexPriceCheck.checkPriceManipulation(
            oracleToken0, oracleToken1, token0, token1, true, address(pool), getCurrentSqrtPrice()
        );
    }

    /// @inheritdoc BaseDexVault
    function _getTokenLiquidity(uint256 tokenId) internal view virtual override returns (uint128 liquidity) {
        (,,,,,, liquidity,,,,) = positionManager.positions(tokenId);
    }

    /// @inheritdoc BaseDexVault
    function _getTokensOwed(uint256 tokenId)
        internal
        view
        virtual
        override
        returns (uint128 amount0, uint128 amount1)
    {
        (,,,,,,,,, amount0, amount1) = positionManager.positions(tokenId);
    }

    /// @inheritdoc BaseDexVault
    function _updateTicks() internal virtual override {
        int24 tickUpper_ = TickMath.MAX_TICK - TickMath.MAX_TICK % pool.tickSpacing();
        _setTicks(-tickUpper_, tickUpper_);
    }

    /// @inheritdoc BaseDexUniformVault
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
        returns (uint256 tokenId, uint256 amount0Used, uint256 amount1Used)
    {
        (tokenId,, amount0Used, amount1Used) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
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

    /**
     * @notice Callback function for swaps
     * @param amount0Delta The change in token0 amount
     * @param amount1Delta The change in token1 amount
     * @param data Additional data needed to process the callback
     */
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
