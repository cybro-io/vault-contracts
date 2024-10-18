// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {BaseVault, IERC20Metadata, ERC20Upgradeable} from "./BaseVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStargatePool} from "./interfaces/stargate/IStargatePool.sol";
import {IStargateStaking} from "../src/interfaces/stargate/IStargateStaking.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

contract StargateVault is BaseVault, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    IStargatePool public immutable pool;

    address public immutable lpToken;

    IStargateStaking public immutable staking;

    IERC20Metadata public immutable stg;

    IERC20Metadata public immutable weth;

    bool internal immutable _stgForWeth;

    bool internal immutable _usdtForWeth;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    IUniswapV3Pool public swapPool;
    IUniswapV3Pool public swapPoolUSDTWETH;

    constructor(
        IStargatePool _pool,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        IStargateStaking _staking,
        IERC20Metadata _stg,
        IERC20Metadata _weth
    ) BaseVault(IERC20Metadata(_pool.token()), _feeProvider, _feeRecipient) {
        pool = _pool;
        weth = _weth;
        stg = _stg;
        _stgForWeth = stg < weth;
        _usdtForWeth = address(weth) < asset();
        lpToken = pool.lpToken();
        staking = _staking;

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol) public initializer {
        IERC20Metadata(asset()).forceApprove(address(pool), type(uint256).max);
        IERC20Metadata(lpToken).forceApprove(address(staking), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin);
    }

    function setSwapPools(IUniswapV3Pool _swapPool, IUniswapV3Pool _swapPoolUSDTWETH) external onlyOwner {
        swapPool = _swapPool;
        swapPoolUSDTWETH = _swapPoolUSDTWETH;
    }

    function _swap(bool isStgForWeth, uint256 amount) internal returns (uint256) {
        int256 amount0;
        int256 amount1;
        if (isStgForWeth) {
            (amount0, amount1) = swapPool.swap(
                address(this), _stgForWeth, int256(amount), TickMath.MIN_SQRT_RATIO + 1, abi.encode(stg, weth)
            );
            return uint256(-(_stgForWeth ? amount1 : amount0));
        } else {
            (amount0, amount1) = swapPoolUSDTWETH.swap(
                address(this), _usdtForWeth, int256(amount), TickMath.MIN_SQRT_RATIO + 1, abi.encode(asset(), weth)
            );
            return uint256(-(_usdtForWeth ? amount1 : amount0));
        }
    }

    function claimReinvest(uint256 minAssetsWETH, uint256 minAssetsUnderlying) external onlyOwner {
        address[] memory tokens = new address[](1);
        tokens[0] = lpToken;
        staking.claim(tokens);

        // Execute the swap and capture the output amount
        uint256 assets = _swap(true, stg.balanceOf(address(this)));

        // assert minAssets
        if (assets < minAssetsWETH) {
            revert("StargateVault: swap failed");
        }
        if (asset() != address(weth)) {
            assets = _swap(false, assets);
            if (assets < minAssetsUnderlying) {
                revert("StargateVault: swap failed");
            }
        }

        pool.deposit(address(this), assets);
        staking.deposit(address(lpToken), assets);
    }

    function totalAssets() public view override returns (uint256) {
        return staking.balanceOf(lpToken, address(this));
    }

    function _deposit(uint256 assets) internal override {
        assets = pool.deposit(address(this), assets);
        staking.deposit(address(lpToken), assets);
    }

    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * staking.balanceOf(lpToken, address(this)) / totalSupply();
        staking.withdraw(lpToken, assets);
        pool.redeem(assets, address(this));
    }

    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(pool);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Ensure the callback is being called by the correct pool
        require(amount0Delta > 0 || amount1Delta > 0);
        require(
            msg.sender == address(swapPool) || msg.sender == address(swapPoolUSDTWETH),
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
}
