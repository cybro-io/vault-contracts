// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {BaseVault} from "../BaseVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {IHypervisor} from "../interfaces/gamma/IHypervisor.sol";
import {IUniProxy} from "../interfaces/gamma/IUniProxy.sol";
import {IAlgebraPool} from "../interfaces/algebra/IAlgebraPoolV1_9.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {DexPriceCheck} from "../libraries/DexPriceCheck.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";

/**
 * @title GammaAlgebraVault
 * @dev This contract interacts with Algebra Pool and Gamma Hypervisor to manage a vault with liquidity provision.
 */
contract GammaAlgebraVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    bool public immutable isToken0;
    IAlgebraPool public immutable pool;
    IUniProxy public immutable uniProxy;
    IHypervisor public immutable hypervisor;
    IChainlinkOracle public immutable oracleToken0;
    IChainlinkOracle public immutable oracleToken1;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Sets the initial state of the Vault
     * @param _hypervisor Address of the gamma hypervisor contract
     * @param _uniProxy Address of the gamma UniProxy contract
     * @param _asset Address of the asset token
     * @param _feeProvider Address of the fee provider
     * @param _feeRecipient Address to which the fees are sent
     */
    constructor(
        address _hypervisor,
        address _uniProxy,
        IERC20Metadata _asset,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        address _oracleToken0,
        address _oracleToken1
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
        oracleToken0 = IChainlinkOracle(_oracleToken0);
        oracleToken1 = IChainlinkOracle(_oracleToken1);
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the vault contract with necessary setup.
     * @param admin The address of the admin
     * @param name The name of the ERC20 token representing shares in the vault
     * @param symbol The symbol of the ERC20 token representing shares in the vault
     * @param manager The address of the manager
     */
    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        IERC20Metadata(token0).forceApprove(address(hypervisor), type(uint256).max);
        IERC20Metadata(token1).forceApprove(address(hypervisor), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        (uint256 amount0, uint256 amount1) = hypervisor.getTotalAmounts();
        return hypervisor.balanceOf(address(this)) * _calculateInBaseToken(amount0, amount1) / hypervisor.totalSupply();
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view override returns (uint256) {
        (uint256 amount0, uint256 amount1) = hypervisor.getTotalAmounts();
        return _calculateInBaseToken(amount0, amount1);
    }

    /**
     * @dev Returns the current square root price for the pool.
     * @return The current square root price
     */
    function getCurrentSqrtPrice() public view returns (uint256) {
        (uint160 sqrtPriceX96,,,,,,,) = pool.globalState();
        return uint256(sqrtPriceX96);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Function to check if the price of the Dex pool is being manipulated
     */
    function _checkPriceManipulation() internal view {
        DexPriceCheck.checkPriceManipulation(
            oracleToken0, oracleToken1, token0, token1, true, address(pool), getCurrentSqrtPrice()
        );
    }
    /// @inheritdoc BaseVault

    function _deposit(uint256 amount) internal override {
        _checkPriceManipulation();
        (uint256 amount0, uint256 amount1, uint256 unusedAmountToken0, uint256 unusedAmountToken1) = _getAmounts(amount);

        uniProxy.deposit(amount0, amount1, address(this), address(hypervisor), [uint256(0), 0, 0, 0]);

        // Return unused tokens back to sender
        if (unusedAmountToken0 > 0) {
            IERC20Metadata(token0).safeTransfer(msg.sender, unusedAmountToken0);
        }
        if (unusedAmountToken1 > 0) {
            IERC20Metadata(token1).safeTransfer(msg.sender, unusedAmountToken1);
        }
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        _checkPriceManipulation();
        // Withdraw assets from the hypervisor proportional to shares
        (uint256 amount0, uint256 amount1) = hypervisor.withdraw(
            shares * hypervisor.balanceOf(address(this)) / totalSupply(),
            address(this),
            address(this),
            [uint256(0), 0, 0, 0]
        );

        // Swap to return assets in terms of the base token
        if (isToken0) {
            assets = amount0 + _swap(false, amount1);
        } else {
            assets = amount1 + _swap(true, amount0);
        }
    }

    /**
     * @dev Swaps tokens using the pool in the desired direction.
     * @param zeroForOne If true, swap token0 for token1, else swap token1 for token0
     * @param amount The amount to swap
     * @return The amount received after swap
     */
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

    /**
     * @dev Calculates and returns the optimal amounts of token0 and token1 based on the supplied amount.
     * @param amount The total amount in the asset of the vault
     * @return amount0 The amount of token0 to use
     * @return amount1 The amount of token1 to use
     * @return unusedAmountToken0 Unused amount of token0
     * @return unusedAmountToken1 Unused amount of token1
     */
    function _getAmounts(uint256 amount) internal returns (uint256, uint256, uint256, uint256) {
        (uint256 amountFor0, uint256 amountFor1) = _getAmountsInAsset(amount);

        uint256 amount0;
        uint256 amount1;
        if (isToken0) {
            amount0 = amountFor0;
            amount1 = _swap(true, amountFor1);
        } else {
            amount0 = _swap(false, amountFor0);
            amount1 = amountFor1;
        }

        (uint256 min1, uint256 max1) = uniProxy.getDepositAmount(address(hypervisor), token0, amount0);
        if (max1 < amount1) {
            return (amount0, max1, 0, amount1 - max1);
        } else if (amount1 < min1) {
            (, uint256 max0) = uniProxy.getDepositAmount(address(hypervisor), token1, amount1);
            return (max0, amount1, amount0 - max0, 0);
        } else {
            return (amount0, amount1, 0, 0);
        }
    }

    /**
     * @dev Calculates how much of each token to use in base assets.
     * Splits the input amount into amounts for token0 and token1 based on current ratios.
     * @param amount Total amount of the base token
     * @return amountFor0 Amount used for token0
     * @return amountFor1 Amount used for token1
     */
    function _getAmountsInAsset(uint256 amount) internal view returns (uint256 amountFor0, uint256 amountFor1) {
        (uint256 totalAmount0, uint256 totalAmount1) = hypervisor.getTotalAmounts();
        uint256 amount1in0 = Math.mulDiv(totalAmount1, 2 ** 192, getCurrentSqrtPrice() ** 2);

        amountFor0 = amount * totalAmount0 / (totalAmount0 + amount1in0);
        amountFor1 = amount - amountFor0;
    }

    /**
     * @dev Converts amounts of token0 and token1 into equivalent amount in base asset.
     * @param amount0 Amount of token0
     * @param amount1 Amount of token1
     * @return Equivalent amount in base token
     */
    function _calculateInBaseToken(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        uint256 sqrtPrice = getCurrentSqrtPrice();
        return isToken0
            ? Math.mulDiv(amount1, 2 ** 192, sqrtPrice * sqrtPrice) + amount0
            : Math.mulDiv(amount0, sqrtPrice * sqrtPrice, 2 ** 192) + amount1;
    }

    /// @inheritdoc BaseVault
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
