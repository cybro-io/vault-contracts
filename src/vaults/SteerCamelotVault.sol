// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {BaseVault} from "../BaseVault.sol";
import {ICamelotMultiPositionLiquidityManager} from "../interfaces/steer/ICamelotMultiPositionLiquidityManager.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAlgebraPool} from "../interfaces/algebra/IAlgebraPoolV1_9.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {DexPriceCheck} from "../libraries/DexPriceCheck.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";

/**
 * @title SteerCamelotVault
 * @notice Vault that interacts with Camelot concentrated liquidity positions through Steer protocol
 */
contract SteerCamelotVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    bool public immutable isToken0;
    IChainlinkOracle public immutable oracleToken0;
    IChainlinkOracle public immutable oracleToken1;

    /// @notice Reference to the Steer protocol's liquidity manager contract
    ICamelotMultiPositionLiquidityManager public immutable steerVault;

    /// @notice Reference to the Camelot pool contract for the token pair
    IAlgebraPool public immutable pool;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the SteerCamelotVault
     * @param _asset The underlying asset of the vault
     * @param _feeRecipient The address that receives fees
     * @param _feeProvider The fee provider contract
     * @param _steerVault Address of the Steer protocol's liquidity manager
     */
    constructor(
        IERC20Metadata _asset,
        address _feeRecipient,
        IFeeProvider _feeProvider,
        address _steerVault,
        address _oracleToken0,
        address _oracleToken1
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        steerVault = ICamelotMultiPositionLiquidityManager(_steerVault);
        pool = IAlgebraPool(steerVault.pool());
        // tokens are already sorted
        token0 = steerVault.token0();
        token1 = steerVault.token1();
        isToken0 = token0 == address(_asset);
        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();
        oracleToken0 = IChainlinkOracle(_oracleToken0);
        oracleToken1 = IChainlinkOracle(_oracleToken1);
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializer function for setting up the vault
     * @param admin The admin address for the vault
     * @param name The name of the ERC20 token
     * @param symbol The symbol of the ERC20 token
     * @param manager The address of the manager
     */
    function initialize(address admin, string memory name, string memory symbol, address manager)
        external
        initializer
    {
        IERC20Metadata(token0).forceApprove(address(steerVault), type(uint256).max);
        IERC20Metadata(token1).forceApprove(address(steerVault), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        (uint256 amount0, uint256 amount1) = steerVault.getTotalAmounts();
        return steerVault.balanceOf(address(this)) * _calculateInBaseToken(amount0, amount1) / steerVault.totalSupply();
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view override returns (uint256) {
        (uint256 amount0, uint256 amount1) = steerVault.getTotalAmounts();
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
    function _deposit(uint256 amount) internal override returns (uint256 totalAssetsBefore) {
        _checkPriceManipulation();
        (uint256 total0, uint256 total1) = steerVault.getTotalAmounts();
        uint256 steerBalance = steerVault.balanceOf(address(this));
        uint256 steerTotalSupply = steerVault.totalSupply();
        (uint256 amount0, uint256 amount1) = _getAmounts(amount);
        if (isToken0) {
            amount1 = _swap(true, amount1);
        } else {
            amount0 = _swap(false, amount0);
        }
        (, uint256 amount0Used, uint256 amount1Used) = steerVault.deposit(amount0, amount1, 0, 0, address(this));

        // Calculate remaining amounts after liquidity provision
        amount0 -= amount0Used;
        amount1 -= amount1Used;

        // Handle remaining tokens and return them to the user if necessary
        if (amount0 > 0 && !isToken0) {
            amount1 += _swap(true, amount0);
            IERC20Metadata(token1).safeTransfer(msg.sender, amount1);
        } else if (amount1 > 0 && isToken0) {
            amount0 += _swap(false, amount1);
            IERC20Metadata(token0).safeTransfer(msg.sender, amount0);
        } else {
            if (isToken0 && amount0 > 0) {
                IERC20Metadata(token0).safeTransfer(msg.sender, amount0);
            } else if (amount1 > 0) {
                IERC20Metadata(token1).safeTransfer(msg.sender, amount1);
            }
        }
        _checkPriceManipulation();
        totalAssetsBefore = steerBalance * _calculateInBaseToken(total0, total1) / steerTotalSupply;
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        _checkPriceManipulation();
        (uint256 amount0, uint256 amount1) =
            steerVault.withdraw(shares * steerVault.balanceOf(address(this)) / totalSupply(), 0, 0, address(this));
        // Swap to return assets in terms of the base token
        if (isToken0) {
            assets = amount0 + _swap(false, amount1);
        } else {
            assets = amount1 + _swap(true, amount0);
        }
        _checkPriceManipulation();
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

    /**
     * @dev Calculates how much of each token to use in base assets.
     * Splits the input amount into amounts for token0 and token1 based on current ratios.
     * @param amount Total amount of the base token
     * @return amountFor0 Amount used for token0
     * @return amountFor1 Amount used for token1
     */
    function _getAmounts(uint256 amount) internal view returns (uint256 amountFor0, uint256 amountFor1) {
        (uint256 totalAmount0, uint256 totalAmount1) = steerVault.getTotalAmounts();
        uint256 amount1in0 = Math.mulDiv(totalAmount1, 2 ** 192, getCurrentSqrtPrice() ** 2);

        amountFor0 = amount * totalAmount0 / (totalAmount0 + amount1in0);
        amountFor1 = amount - amountFor0;
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

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(steerVault);
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
        require(address(pool) == msg.sender, "SteerCamelot: invalid swap callback caller");

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
