// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {BaseVault, IERC20Metadata, ERC20Upgradeable} from "../BaseVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStargatePool} from "../interfaces/stargate/IStargatePool.sol";
import {IStargateStaking} from "../interfaces/stargate/IStargateStaking.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title StargateVault
/// @notice A vault contract for managing Stargate liquidity
contract StargateVault is BaseVault, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    /// @notice The Stargate pool used for deposits and redeems
    IStargatePool public immutable pool;

    /// @notice The LP token for the Stargate pool
    address public immutable lpToken;

    /// @notice The staking contract for Stargate
    IStargateStaking public immutable staking;

    /// @notice The STG token
    IERC20Metadata public immutable stg;

    /// @notice The WETH token
    IERC20Metadata public immutable weth;

    /// @notice Uniswap V3 pool for STG/WETH pair
    IUniswapV3Pool public immutable stgWethPool;

    /// @notice Uniswap V3 pool for asset/WETH pair
    IUniswapV3Pool public immutable assetWethPool;

    /// @notice Conversion rate for asset decimals adjustment
    uint256 internal immutable _convertRate;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /* ========== CONSTRUCTOR ========== */

    /// @notice Constructor for the StargateVault contract
    /// @param _pool Stargate pool used for asset management
    /// @param _feeProvider Fee provider contract
    /// @param _feeRecipient Address to receive fees
    /// @param _staking Staking contract for Stargate
    /// @param _stg STG token contract
    /// @param _weth WETH token contract
    /// @param _stgWethPool Uniswap V3 pool for STG/WETH
    /// @param _assetWethPool Uniswap V3 pool for asset/WETH
    constructor(
        IStargatePool _pool,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        IStargateStaking _staking,
        IERC20Metadata _stg,
        IERC20Metadata _weth,
        IUniswapV3Pool _stgWethPool,
        IUniswapV3Pool _assetWethPool
    ) BaseVault(_pool.token() == address(0) ? _weth : IERC20Metadata(_pool.token()), _feeProvider, _feeRecipient) {
        pool = _pool;
        weth = _weth;
        stg = _stg;
        lpToken = pool.lpToken();
        staking = _staking;
        stgWethPool = _stgWethPool;
        assetWethPool = _assetWethPool;
        _convertRate = 10 ** (18 - _pool.sharedDecimals());

        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /// @notice Initializer function for setting up the vault
    /// @param admin The admin address for the vault
    /// @param name The name of the ERC20 token
    /// @param symbol The symbol of the ERC20 token
    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        IERC20Metadata(asset()).forceApprove(address(pool), type(uint256).max);
        IERC20Metadata(lpToken).forceApprove(address(staking), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @notice Claims rewards, swaps them for the underlying asset and reinvests
    /// @param minAssets Minimum amount of assets to receive from the swap
    /// @return assets The amount of assets obtained and reinvested
    function claimReinvest(uint256 minAssets) external onlyRole(MANAGER_ROLE) returns (uint256 assets) {
        address[] memory tokens = new address[](1);
        tokens[0] = lpToken;
        staking.claim(tokens);

        // Execute the swap and capture the output amount
        assets = _swapToAssets(stg.balanceOf(address(this)));

        if (assets < minAssets) {
            revert("StargateVault: slippage");
        }

        _deposit(assets);
    }

    /* ========== VIEW METHODS ========== */

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        return staking.balanceOf(lpToken, address(this));
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view virtual override returns (uint256) {
        return pool.tvl();
    }

    /* ========== INTERNAL METHODS ========== */

    /// @notice Internal method for depositing assets into the Stargate pool and staking
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        if (asset() == address(weth)) {
            // if assets lower then convertRate assetToDeposit will be 0
            // And transaction will be reverted
            uint256 assetToDeposit = SafeCast.toUint64(assets / _convertRate) * _convertRate;
            _unwrapETH(assetToDeposit);
            pool.deposit{value: assetToDeposit}(address(this), assetToDeposit);
            if (assets > assetToDeposit) {
                weth.safeTransfer(msg.sender, assets - assetToDeposit);
                assets = assetToDeposit;
            }
        } else {
            assets = pool.deposit(address(this), assets);
        }
        staking.deposit(lpToken, assets);
    }

    /// @notice Redeems shares from the Stargate pool
    /// @param shares The amount of shares to redeem
    /// @return assets The amount of assets obtained from redeeming
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * staking.balanceOf(lpToken, address(this)) / totalSupply();
        staking.withdraw(lpToken, assets);
        assets = pool.redeem(assets, address(this));
        if (asset() == address(weth)) {
            _wrapETH(assets);
        }
    }

    /// @notice Swaps tokens to the vault's designated asset using Uniswap V3
    /// @param amount The amount of tokens to swap
    /// @return assets The amount of the asset obtained from the swap
    function _swapToAssets(uint256 amount) internal returns (uint256 assets) {
        bool zeroForOne = stg < weth;
        (int256 amount0, int256 amount1) = stgWethPool.swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            zeroForOne ? abi.encode(stg, weth) : abi.encode(weth, stg)
        );
        assets = uint256(-(zeroForOne ? amount1 : amount0));
        if (asset() != address(weth)) {
            zeroForOne = address(weth) < asset();
            (amount0, amount1) = assetWethPool.swap(
                address(this),
                zeroForOne,
                int256(assets),
                zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                zeroForOne ? abi.encode(weth, asset()) : abi.encode(asset(), weth)
            );
            assets = uint256(-(zeroForOne ? amount1 : amount0));
        }
    }

    /// @notice Wraps ETH into WETH
    /// @param amount The amount of ETH to wrap
    function _wrapETH(uint256 amount) internal {
        IWETH(asset()).deposit{value: amount}();
    }

    /// @notice Unwraps WETH into ETH
    /// @param amount The amount of WETH to unwrap
    function _unwrapETH(uint256 amount) internal {
        IWETH(asset()).withdraw(amount);
    }

    /// @notice Validates if a token can be recovered
    /// @param token The address of the token to validate
    /// @return True if the token can be recovered, false otherwise
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(pool);
    }

    /// @notice Uniswap V3 swap callback for providing required token amounts during swaps
    /// @param amount0Delta Amount of the first token delta
    /// @param amount1Delta Amount of the second token delta
    /// @param data Encoded data containing swap details
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(amount0Delta > 0 || amount1Delta > 0);
        require(
            msg.sender == address(stgWethPool) || msg.sender == address(assetWethPool),
            "StargateVault: invalid swap callback caller"
        );

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

    /// @notice Allows contract to receive ETH from the pool or WETH withdrawals
    receive() external payable {
        require(msg.sender == address(pool) || msg.sender == address(weth));
    }
}
