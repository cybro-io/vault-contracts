// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVault} from "./BaseVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {IHypervisor} from "./interfaces/gamma/IHypervisor.sol";
import {IUniProxy} from "./interfaces/gamma/IUniProxy.sol";
import {IAlgebraPool} from "./interfaces/algebra/IAlgebraPoolV1_9.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import {IClearingV2} from "./interfaces/gamma/IClearingV2.sol";

contract GammaAlgebraVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    uint256 public constant PRECISION = 1e36;

    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    bool public immutable isToken0;
    IAlgebraPool public immutable pool;
    IUniProxy public immutable uniProxy;
    IHypervisor public immutable hypervisor;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _hypervisor,
        address _uniProxy,
        IERC20Metadata _asset,
        IFeeProvider _feeProvider,
        address _feeRecipient
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        hypervisor = IHypervisor(_hypervisor);
        uniProxy = IUniProxy(_uniProxy);
        // tokens are already sorted
        token0 = hypervisor.token0();
        token1 = hypervisor.token1();
        isToken0 = token0 == address(_asset);
        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();
        pool = IAlgebraPool(hypervisor.pool());
    }

    /* ========== INITIALIZER ========== */

    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        IERC20Metadata(token0).forceApprove(address(hypervisor), type(uint256).max);
        IERC20Metadata(token1).forceApprove(address(hypervisor), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function totalAssets() public view override returns (uint256) {
        (uint256 amount0, uint256 amount1) = hypervisor.getTotalAmounts();
        return hypervisor.balanceOf(address(this)) * _calculateInBaseToken(amount0, amount1) / hypervisor.totalSupply();
    }

    function underlyingTVL() external view override returns (uint256) {
        (uint256 amount0, uint256 amount1) = hypervisor.getTotalAmounts();
        return _calculateInBaseToken(amount0, amount1);
    }

    function _getCurrentSqrtPrice() internal view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,,) = pool.globalState();
        return uint256(sqrtPriceX96);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _deposit(uint256 amount) internal override {
        (uint256 amount0, uint256 amount1) = _getAmounts(amount);
        uint256 unusedAnmountInAsset = amount - amount0 - amount1;
        if (isToken0) {
            amount1 = _swap(true, amount1);
            (uint256 amountMinByUni, uint256 amountMaxByUni) =
                uniProxy.getDepositAmount(address(hypervisor), asset(), amount0);
            if (amountMaxByUni < amount1) {
                uint256 newAmount = amountMinByUni + (amountMaxByUni - amountMinByUni) / 2;
                unusedAnmountInAsset += _swap(false, amount1 - newAmount);
                amount1 = newAmount;
            }
        } else {
            amount0 = _swap(false, amount0);
            (uint256 amountMinByUni, uint256 amountMaxByUni) =
                uniProxy.getDepositAmount(address(hypervisor), asset(), amount1);
            if (amountMaxByUni < amount0) {
                uint256 newAmount = amountMinByUni + (amountMaxByUni - amountMinByUni) / 2;
                unusedAnmountInAsset += _swap(true, amount0 - newAmount);
                amount0 = newAmount;
            }
        }

        uniProxy.deposit(amount0, amount1, address(this), address(hypervisor), [uint256(0), 0, 0, 0]);

        if (unusedAnmountInAsset > 0) {
            IERC20Metadata(asset()).safeTransfer(msg.sender, unusedAnmountInAsset);
        }
    }

    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        (uint256 amount0, uint256 amount1) = hypervisor.withdraw(
            shares * hypervisor.balanceOf(address(this)) / totalSupply(),
            address(this),
            address(this),
            [uint256(0), 0, 0, 0]
        );
        if (isToken0) {
            assets = amount0 + _swap(false, amount1);
        } else {
            assets = amount1 + _swap(true, amount0);
        }
    }

    function _swap(bool zeroForOne, uint256 amount) internal returns (uint256) {
        (int256 amount0, int256 amount1) = pool.swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            zeroForOne ? abi.encode(token0, token1) : abi.encode(token1, token0)
        );
        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    function _getAmounts(uint256 amount) internal view returns (uint256 amountFor0, uint256 amountFor1) {
        (uint256 totalamount0, uint256 totalamount1) = hypervisor.getTotalAmounts();
        uint256 sqrtPriceX96 = _getCurrentSqrtPrice();
        uint256 totalamount1in0 = FullMath.mulDiv(totalamount1, 2 ** 192, sqrtPriceX96 ** 2);
        uint256 ratio = totalamount1in0 * PRECISION / totalamount0;
        if (isToken0) {
            amountFor1 = FullMath.mulDiv(amount, ratio, ratio + PRECISION);
            amountFor0 = amount - amountFor1;
        } else {
            amountFor0 = FullMath.mulDiv(amount, PRECISION, ratio + PRECISION);
            amountFor1 = amount - amountFor0;
        }
    }

    function _calculateInBaseToken(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        uint256 sqrtPrice = _getCurrentSqrtPrice();
        return isToken0
            ? Math.mulDiv(amount1, 2 ** 192, sqrtPrice * sqrtPrice) + amount0
            : Math.mulDiv(amount0, sqrtPrice * sqrtPrice, 2 ** 192) + amount1;
    }

    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(hypervisor);
    }

    /* ========== CALLBACK FUNCTIONS ========== */

    /**
     * @notice Callback function for swaps
     * @param amount0Delta The change in token0 amount
     * @param amount1Delta The change in token1 amount
     * @param data Additional data needed to process the callback
     */
    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
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
