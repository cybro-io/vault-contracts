// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {BaseVault, IERC20Metadata} from "../BaseVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {OracleData} from "../libraries/OracleData.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

/**
 * @title LidoVault
 * @notice This contract accumulates wstETH by swapping vault's asset into wstETH through the dex pools.
 */
contract LidoVault is BaseVault, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20Metadata;
    using OracleData for IChainlinkOracle;

    /* ========== ERRORS ========== */

    error InvalidSwapCallbackCaller();

    /* ========== IMMUTABLE VARIABLES ========== */

    /// @notice The oracle used to get the wstETH/ETH price
    IChainlinkOracle public immutable oracle;

    /// @notice The wstETH token
    IERC20Metadata public immutable wstETH;

    /// @notice The Uniswap V3 pool for the asset and wstETH
    IUniswapV3Pool public immutable pool;

    /// @notice Indicates if the asset is the first token in the pool
    bool public immutable isToken0;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(
        IERC20Metadata _asset,
        IUniswapV3Pool _pool,
        IChainlinkOracle _oracle,
        IERC20Metadata _wstETH,
        IFeeProvider _feeProvider,
        address _feeRecipient
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        oracle = _oracle;
        wstETH = _wstETH;
        isToken0 = _asset < _wstETH;
        pool = _pool;

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        return _getPrice() * wstETH.balanceOf(address(this)) / (10 ** wstETH.decimals());
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view virtual override returns (uint256) {
        return _getPrice() * wstETH.totalSupply() / (10 ** wstETH.decimals());
    }

    /**
     * @dev Returns the current square root price for the pool. (x96)
     * @return The current square root price (x96)
     */
    function getCurrentSqrtPrice() public view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        return uint256(sqrtPriceX96);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function _deposit(uint256 assets) internal override returns (uint256 totalAssetsBefore) {
        totalAssetsBefore = _totalAssetsPrecise();
        _swap(isToken0, assets);
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = _swap(!isToken0, shares * wstETH.balanceOf(address(this)) / totalSupply());
    }

    /**
     * @dev Returns the price of the wstETH/asset.
     * @return The price of the wstETH/asset.
     */
    function _getPrice() internal view returns (uint256) {
        return uint256(oracle.getPrice()) * (10 ** decimals()) / 10 ** (oracle.decimals());
    }

    /**
     * @dev Swaps tokens using the pool in the desired direction.
     * @param zeroForOne If true, swap asset for wstETH, else swap wstETH for asset
     * @param amount The amount to swap
     * @return The amount received after swap
     */
    function _swap(bool zeroForOne, uint256 amount) internal returns (uint256) {
        (int256 amount0, int256 amount1) = pool.swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            zeroForOne == isToken0 ? abi.encode(asset(), address(wstETH)) : abi.encode(address(wstETH), asset())
        );
        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(wstETH);
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    /**
     * @notice Uniswap V3 swap callback for providing required token amounts during swaps
     * @param amount0Delta Amount of the first token delta
     * @param amount1Delta Amount of the second token delta
     * @param data Encoded data containing swap details
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(amount0Delta > 0 || amount1Delta > 0);
        (address tokenIn,) = abi.decode(data, (address, address));

        require(address(pool) == msg.sender, InvalidSwapCallbackCaller());

        // Transfer the required amount back to the pool
        IERC20Metadata(tokenIn).safeTransfer(msg.sender, uint256(amount0Delta > 0 ? amount0Delta : amount1Delta));
    }
}
