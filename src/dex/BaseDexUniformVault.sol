// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {BaseVault} from "../BaseVault.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

/**
 * @title BaseDexUniformVault
 * @notice This abstract contract provides a base implementation for managing liquidity on a decentralized exchange (DEX)
 * @dev This contract is meant to be inherited by specific implementations for different DEXes
 */
abstract contract BaseDexUniformVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    error StalePrice();
    error RoundNotComplete();
    error ChainlinkPriceReportingZero();
    error PriceManipulation();

    /// @notice Precision for slippage
    uint32 public constant slippagePrecision = 10000;

    /// @notice Maximum slippage
    uint32 public constant maxSlippage = 200;

    /* ========== IMMUTABLE VARIABLES ========== */

    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    bool public immutable isToken0;
    IChainlinkOracle public immutable oracleToken0;
    IChainlinkOracle public immutable oracleToken1;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor that sets the initial token addresses and their respective decimals
     * @param _token0 The address of token0
     * @param _token1 The address of token1
     * @param _asset The base token of the vault
     * @param _feeProvider The fee provider contract
     * @param _feeRecipient The address that receives the fees
     */
    constructor(
        address _token0,
        address _token1,
        IERC20Metadata _asset,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        address _oracleToken0,
        address _oracleToken1
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        (token0, token1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);
        isToken0 = token0 == address(_asset);
        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();
        oracleToken0 = IChainlinkOracle(_oracleToken0);
        oracleToken1 = IChainlinkOracle(_oracleToken1);
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the contract with the given admin address
     * @dev This function should be called once during deployment to set up the ownership
     * @param admin The address of the admin
     * @param manager The address of the manager
     */
    function __BaseDexUniformVault_init(address admin, address manager) public onlyInitializing {
        __BaseVault_init(admin, manager);
    }

    modifier checkPriceManipulation() {
        uint256 deviation = (getCurrentSqrtPrice() ** 2) * slippagePrecision / (getTrustedSqrtPrice() ** 2);
        if ((deviation < slippagePrecision - maxSlippage) || (deviation > slippagePrecision + maxSlippage)) {
            revert PriceManipulation();
        }
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Retrieves the amounts of token0 and token1 that correspond to the current liquidity
     * @dev Must be implemented by the inheriting contract to provide specific logic for the DEX
     * @return amount0 The amount of token0
     * @return amount1 The amount of token1
     */
    function getPositionAmounts() public view virtual returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Abstract function to retrieve the current square root price of the Dex pool
     * @dev Must be implemented by the inheriting contract
     * @return The current square root price
     */
    function getCurrentSqrtPrice() public view virtual returns (uint256);

    function getTrustedSqrtPrice() public view virtual returns (uint256) {
        if (address(oracleToken0) == address(0)) {
            return getTwap();
        } else {
            return getSqrtPriceFromOracles();
        }
    }

    /**
     * @dev Calculates the square root of the price ratio between two tokens based on data from oracle.
     */
    function getSqrtPriceFromOracles() public view returns (uint256) {
        return Math.sqrt(Math.mulDiv(_getPrice(token0), 2 ** 96, _getPrice(token1)))
            * Math.sqrt(Math.mulDiv(10 ** token1Decimals, 2 ** 96, 10 ** token0Decimals));
    }

    function getTwap() public view virtual returns (uint256) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0;
        secondsAgos[1] = 1800;

        (int56[] memory tickCumulatives) = _observe(secondsAgos);
        int56 tickCumulativeDelta = tickCumulatives[0] - tickCumulatives[1];
        int56 timeElapsed = int56(uint56(secondsAgos[1]));

        int24 averageTick = int24(tickCumulativeDelta / timeElapsed);
        if (tickCumulativeDelta < 0 && (tickCumulativeDelta % timeElapsed != 0)) {
            averageTick--;
        }

        return uint256(TickMath.getSqrtRatioAtTick(averageTick));
    }

    /// @inheritdoc BaseVault
    function totalAssets() public view virtual override returns (uint256 totalValue) {
        (uint256 total0, uint256 total1) = getPositionAmounts();
        totalValue = _calculateInBaseToken(total0, total1);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _observe(uint32[] memory secondsAgos) internal view virtual returns (int56[] memory tickCumulatives);

    /**
     * @notice Gets the latest price for a token using oracle
     * @param token The address of the token
     * @return The latest price from the oracle
     */
    function _getPrice(address token) internal view virtual returns (uint256) {
        IChainlinkOracle oracle = token == token0 ? oracleToken0 : oracleToken1;
        (uint80 roundID, int256 price,, uint256 timestamp, uint80 answeredInRound) = oracle.latestRoundData();

        if (answeredInRound < roundID) revert StalePrice();
        if (timestamp == 0) revert RoundNotComplete();
        if (price <= 0) revert ChainlinkPriceReportingZero();

        // returns price in the vault decimals
        return uint256(price) * (10 ** decimals()) / 10 ** (oracle.decimals());
    }

    /**
     * @notice Retrieves the current liquidity of the Dex position
     * @return liquidity The current liquidity of the position
     */
    function _getTokenLiquidity() internal view virtual returns (uint256 liquidity);

    /**
     * @notice Internal function to perform a token swap on the DEX
     * @param zeroForOne Whether to swap token0 for token1 (true) or token1 for token0 (false)
     * @param amount The amount of tokens to swap
     * @return The amount of tokens received from the swap
     */
    function _swap(bool zeroForOne, uint256 amount) internal virtual returns (uint256);

    /**
     * @notice Internal function to add liquidity to the DEX
     * @param amount0 The amount of token0 to add
     * @param amount1 The amount of token1 to add
     * @return amount0Used The amount of token0 actually used in the liquidity addition
     * @return amount1Used The amount of token1 actually used in the liquidity addition
     */
    function _addLiquidity(uint256 amount0, uint256 amount1)
        internal
        virtual
        returns (uint256 amount0Used, uint256 amount1Used);

    /**
     * @notice Internal function to remove liquidity from the DEX
     * @param liquidity The amount of liquidity to remove
     * @return The amounts of token0 and token1 withdrawn
     */
    function _removeLiquidity(uint256 liquidity) internal virtual returns (uint256, uint256);

    /**
     * @notice Calculates the amounts neeeded to get swapped into token0 and token1 to place a position in the given range.
     * @param amount The total assets to be divided between token0 and token1
     * @return amountFor0 The amount of token0 to be added
     * @return amountFor1 The amount of token1 to be added
     */
    function _getAmounts(uint256 amount) internal virtual returns (uint256 amountFor0, uint256 amountFor1);

    /**
     * @notice Calculates the amount of tokens in base token
     * @param amount0 The amount of token0
     * @param amount1 The amount of token1
     * @return The amount of tokens in base token
     */
    function _calculateInBaseToken(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        uint256 sqrtPrice = getCurrentSqrtPrice();
        return isToken0
            ? Math.mulDiv(amount1, 2 ** 192, sqrtPrice * sqrtPrice) + amount0
            : Math.mulDiv(amount0, sqrtPrice * sqrtPrice, 2 ** 192) + amount1;
    }

    /// @inheritdoc BaseVault
    function _deposit(uint256 assets) internal virtual override checkPriceManipulation {
        (uint256 amount0, uint256 amount1) = _getAmounts(assets);

        if (isToken0) {
            amount0 = amount0;
            amount1 = _swap(true, amount1);
        } else {
            amount0 = _swap(false, amount0);
            amount1 = amount1;
        }

        (uint256 amount0Used, uint256 amount1Used) = _addLiquidity(amount0, amount1);

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
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal virtual override checkPriceManipulation returns (uint256 assets) {
        (uint256 amount0, uint256 amount1) = _removeLiquidity(shares * _getTokenLiquidity() / totalSupply());

        // Calculate the assets to return based on the desired output token
        if (isToken0) {
            assets = amount0 + _swap(false, amount1);
        } else {
            assets = amount1 + _swap(true, amount0);
        }
    }
}
