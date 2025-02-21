// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseVault} from "./BaseVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IVault} from "./interfaces/IVault.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

/**
 * @title SeasonalVault
 * @notice Vault that manages assets based on crypto market seasons strategy
 * @dev Implements seasonal strategy for crypto asset management
 */
contract SeasonalVault is BaseVault, IUniswapV3SwapCallback, IERC721Receiver {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.UintSet;

    /* ========== EVENTS ========== */

    struct Position {
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
    }

    /* ========== CONSTANTS ========== */

    uint256 public constant PRECISION = 1e24;

    /// @notice Precision for slippage
    uint32 public constant slippagePrecision = 10000;

    /* ========== IMMUTABLE VARIABLES ========== */

    IERC20Metadata public immutable token0;
    IERC20Metadata public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    IVault public immutable token0Vault;
    IVault public immutable token1Vault;

    INonfungiblePositionManager public immutable positionManager;

    /// @notice Maximum slippage tolerance
    uint32 public maxSlippage;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice Set of token IDs for managed Uniswap positions
    EnumerableSet.UintSet _tokenIds;

    /// @notice Mapping of token IDs to Uniswap positions
    mapping(uint256 tokenId => Position position) public positions;

    /// @notice Maps fee tiers to pool addresses
    mapping(uint24 fee => address pool) public pools;

    /// @notice Maps fee tiers to tick spacings
    mapping(uint24 fee => int24 tickSpacing) public feeAmountTickSpacing;

    /// @notice Mapping of tokens to their oracles
    mapping(address token => IChainlinkOracle oracle) public oracles;

    /**
     * @notice The address of the token that is being accumulated
     * in the vault during the current period
     */
    IERC20Metadata public tokenTreasure;

    /// @notice The lowest tick of all current positions
    int24 public lowestTick;

    /// @notice The highest tick of all current positions
    int24 public highestTick;

    /**
     * @notice The difference between the worst and the current
     * ticks used for closePositionsBadMarket()
     */
    int24 public tickDiff;

    /// @notice The fee of the pool used for immediate token exchange
    uint24 public feeForSwaps;

    /// @notice Identifies if token0 is the "treasure" token
    bool public isToken0;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Sets up the SeasonalVault with initial parameters.
     * @param _positionManager Address of the Uniswap V3 position manager
     * @param _asset The underlying asset of the vault
     * @param _token0 Address of the first token in the pool
     * @param _token1 Address of the second token in the pool
     * @param _feeProvider Address of the fee provider
     * @param _feeRecipient Address receiving the fees
     * @param _token0Vault Vault for token0
     * @param _token1Vault Vault for token1
     */
    constructor(
        address payable _positionManager,
        IERC20Metadata _asset,
        address _token0,
        address _token1,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        IVault _token0Vault,
        IVault _token1Vault
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        positionManager = INonfungiblePositionManager(_positionManager);
        (token0, token1, token0Vault, token1Vault) = _token0 < _token1
            ? (IERC20Metadata(_token0), IERC20Metadata(_token1), _token0Vault, _token1Vault)
            : (IERC20Metadata(_token1), IERC20Metadata(_token0), _token1Vault, _token0Vault);
        token0Decimals = token0.decimals();
        token1Decimals = token1.decimals();
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @dev Initializes the vault after deployment.
     * @param admin Address of the admin
     * @param name Name of the vault token
     * @param symbol Symbol of the vault token
     * @param manager Address managing the vault
     */
    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        IERC20Metadata(token0).forceApprove(address(positionManager), type(uint256).max);
        IERC20Metadata(token1).forceApprove(address(positionManager), type(uint256).max);
        IERC20Metadata(token0).forceApprove(address(token0Vault), type(uint256).max);
        IERC20Metadata(token1).forceApprove(address(token1Vault), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
        tokenTreasure = IERC20Metadata(token0);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256 total) {
        (uint256 total0, uint256 total1) = getPositionAmounts();
        (uint256 amount0, uint256 amount1) = _getAmountsForFarmings();
        return _getInUnderlyingAsset(address(token0), total0 + token0.balanceOf(address(this)) + amount0)
            + _getInUnderlyingAsset(address(token1), total1 + token1.balanceOf(address(this)) + amount1);
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view virtual override returns (uint256) {
        // now only from farmings
        return token0Vault.underlyingTVL() + token1Vault.underlyingTVL();
    }

    /**
     * @notice Calculates and returns the total amounts of tokens held across all positions in the vault.
     * @dev This includes the amounts derived from liquidity positions using the current pool price
     *      and adds any tokens owed from the positions.
     * @return amount0 The total amount of token0, including liquidity and owed tokens
     * @return amount1 The total amount of token1, including liquidity and owed tokens
     */
    function getPositionAmounts() public view returns (uint256 amount0, uint256 amount1) {
        (amount0, amount1) = _getTokensOwedForAllPositions();
        // We're using sqrt price from oracle to avoid pool price manipulations affect the result
        uint160 currentSqrtPrice = _getOracleSqrtPriceX96();
        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            uint256 tokenId = _tokenIds.at(i);
            Position memory position = positions[tokenId];
            uint128 liquidity = _getTokenLiquidity(tokenId);
            (uint256 amount0_, uint256 amount1_) = LiquidityAmounts.getAmountsForLiquidity(
                currentSqrtPrice,
                TickMath.getSqrtRatioAtTick(position.tickLower),
                TickMath.getSqrtRatioAtTick(position.tickUpper),
                liquidity
            );
            amount0 += amount0_;
            amount1 += amount1_;
        }
    }

    /**
     * @notice Calculates the potential amounts of tokens assuming the price traverses the entire range,
     *         fully swapping one token into the other.
     * @dev This includes the scenarios where the liquidity positions are entirely converted from one token
     *      to the other based on the full range tick boundaries.
     *      Additionally, it adds any tokens that are currently owed from the positions.
     * @return amount The total potential amount of treasure token
     */
    function getTreasureAmountForFullRange() public view returns (uint256 amount) {
        (uint128 owed0, uint128 owed1) = _getTokensOwedForAllPositions();

        if (isToken0) {
            amount += owed0;
        } else {
            amount += owed1;
        }

        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            uint256 tokenId = _tokenIds.at(i);
            Position memory position = positions[tokenId];
            uint128 liquidity = _getTokenLiquidity(tokenId);
            if (isToken0) {
                amount += LiquidityAmounts.getAmount0ForLiquidity(
                    TickMath.getSqrtRatioAtTick(position.tickLower),
                    TickMath.getSqrtRatioAtTick(position.tickUpper),
                    liquidity
                );
            } else {
                amount += LiquidityAmounts.getAmount1ForLiquidity(
                    TickMath.getSqrtRatioAtTick(position.tickLower),
                    TickMath.getSqrtRatioAtTick(position.tickUpper),
                    liquidity
                );
            }
        }
    }

    /**
     * @notice Optimistically calculates the percentage of the TVL represented by the treasure token.
     * @dev Assumes that all LP positions are fully converted into the treasure token as if the price has passed the entire range.
     *      Assets are considered from three sources: free funds, farming projects, and Uniswap LP positions.
     *      This calculation provides an optimistic view by presuming total conversion of liquidity positions into the treasure token.
     *
     * @return The percentage of the fund held as the treasure token.
     */
    function getNettoPartForTokenOptimistic() public view returns (uint256) {
        uint256 totalTreasureAmount = getTreasureAmountForFullRange() + tokenTreasure.balanceOf(address(this))
            + (isToken0 ? token0Vault : token1Vault).getBalanceInUnderlying(address(this));

        return _getInUnderlyingAsset(address(tokenTreasure), totalTreasureAmount) * PRECISION / totalAssets();
    }

    /**
     * @notice Calculates the percentage of the TVL represented by the token.
     *
     * @return A percentage of the fund held in the particular token
     */
    function getNettoPartForTokenReal(IERC20Metadata inAsset) public view returns (uint256) {
        return _getNettoPartForTokenReal(inAsset, 0);
    }

    /**
     * @notice Calculates the total value locked (TVL) in the vault.
     * @dev This includes the amounts derived from liquidity positions using the current pool price
     *      and adds any tokens owed from the positions and the amounts of tokens in the farming positions.
     * @param inAsset The address of the asset to calculate the total value locked in
     * @return The total value locked in the vault
     */
    function getNettoTVL(address inAsset) public view returns (uint256) {
        return _convert(asset(), inAsset, totalAssets());
    }

    /**
     * @notice Retrieves the current tick of a Uniswap pool.
     * @param pool The address of the Uniswap pool
     * @return tick The current tick of the pool
     */
    function getCurrentTick(address pool) public view returns (int24 tick) {
        (, tick,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    /**
     * @notice Retrieves the current square root price of a Uniswap pool.
     * @param pool The address of the Uniswap pool
     * @return sqrtPriceX96 The current square root price of the pool
     */
    function getCurrentSqrtPrice(address pool) public view returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    /**
     * @notice Returns token IDs of all positions
     * @return Array of token IDs
     */
    function getTokenIds() external view returns (uint256[] memory) {
        return _tokenIds.values();
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Sets the current slippage tolerance
     * @param _maxSlippage Slippage value
     */
    function setMaxSlippage(uint32 _maxSlippage) external onlyRole(MANAGER_ROLE) {
        maxSlippage = _maxSlippage;
    }

    /**
     * @notice Sets the difference between the current tick and the worst tick.
     * @param tickDiff_ The difference between the current tick and the worst tick.
     */
    function setTickDiff(int24 tickDiff_) external onlyRole(MANAGER_ROLE) {
        tickDiff = tickDiff_;
    }

    /**
     * @notice Sets the treasure token.
     * @param token_ The address of the treasure token.
     */
    function setTreasureToken(address token_) external onlyRole(MANAGER_ROLE) {
        require(token_ == address(token0) || token_ == address(token1), "Invalid token");
        tokenTreasure = IERC20Metadata(token_);
        isToken0 = tokenTreasure == token0;
        _recalculateTicks();
    }

    /**
     * @notice Sets the fee for token swaps.
     * @param fee_ The fee for token swaps.
     */
    function setFeeForSwaps(uint24 fee_) external onlyRole(MANAGER_ROLE) {
        feeForSwaps = fee_;
    }

    /**
     * @notice Sets the oracles for tokens.
     * @param tokens_ The addresses of the tokens.
     * @param oracles_ The addresses of the oracles.
     */
    function setOracles(address[] calldata tokens_, IChainlinkOracle[] calldata oracles_)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < oracles_.length; i++) {
            oracles[tokens_[i]] = IChainlinkOracle(oracles_[i]);
        }
    }

    /**
     * @notice Updates the pool for a particular fee tier.
     * @param fee The fee tier to update
     * @return pool The address of the updated pool
     */
    function updatePoolForFee(uint24 fee) external onlyRole(MANAGER_ROLE) returns (address pool) {
        pool = IUniswapV3Factory(positionManager.factory()).getPool(address(token0), address(token1), fee);
        pools[fee] = pool;
        feeAmountTickSpacing[fee] = IUniswapV3Pool(pool).tickSpacing();
    }

    /**
     * @notice Deposits free funds into the vaults.
     */
    function investFreeMoney() external onlyRole(MANAGER_ROLE) {
        token0Vault.deposit(token0.balanceOf(address(this)), address(this), 0);
        token1Vault.deposit(token1.balanceOf(address(this)), address(this), 0);
    }

    /**
     * @notice Claims earned fees from the liquidity positions.
     */
    function claimDEX() external onlyRole(MANAGER_ROLE) {
        // Collect earned fees from the liquidity position
        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            _collect(_tokenIds.at(i), type(uint128).max, type(uint128).max);
        }
    }

    /**
     * @notice Adjusts the LP positions by evaluating the desired and actual percentage of the treasure token in the fund.
     * @dev
     * - Calculates the actual optimistic percentage of the treasure in the fund using `getNettoPartForTokenOptimistic`,
     *   storing the result in `currentPercentage`.
     * - Computes the positive difference as the excess percentage of the fund volume
     *   where new LP positions are desired: `max(0, percentageTreasureDesired - currentPercentage)`.
     *
     * If `percentageTreasureAdded > 0`, the following steps are performed:
     * - Determines the absolute amount of excess tokens (to be traded for the treasure) required to open the position.
     * - Withdraws the calculated amount of tokens from farming projects to free them up as direct tokens in the contract's address.
     * - Calls `_openPosition` to open a new position with the specified parameters.
     *
     *
     * @param percentageTreasureDesired The desired percentage of treasure token in the fund.
     * @param price1 The lower bound of the range price.
     * @param price2 The higher bound of the range price.
     * @param fee The fee percentage (e.g., 0.05%, 0.3%, or 1%).
     */
    function openPositionIfNeed(uint256 percentageTreasureDesired, uint160 price1, uint160 price2, uint24 fee)
        external
        onlyRole(MANAGER_ROLE)
    {
        uint256 currentPercentage = getNettoPartForTokenOptimistic();
        if (percentageTreasureDesired <= currentPercentage) return;

        uint160 currentPrice = getCurrentSqrtPrice(_getOrUpdatePool(fee));
        if (price1 > price2) (price1, price2) = (price2, price1);

        if ((isToken0 && currentPrice < price2)) {
            price1 -= (price2 - currentPrice);
            price2 = currentPrice;
        } else if (!isToken0 && currentPrice > price1) {
            price2 += (currentPrice - price1);
            price1 = currentPrice;
        }

        (int24 tickLower, int24 tickUpper) = _adjustTicks(price1, price2, feeAmountTickSpacing[fee]);
        // recalculate ticks
        if (tickUpper > highestTick) highestTick = tickUpper;
        if (tickLower < lowestTick) lowestTick = tickLower;

        uint256 amountToAdd = _convert(
            asset(), address(tokenTreasure), totalAssets() * (percentageTreasureDesired - currentPercentage) / PRECISION
        );

        uint160 priceLower = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 priceUpper = TickMath.getSqrtRatioAtTick(tickUpper);
        if (isToken0) {
            amountToAdd = Math.mulDiv(amountToAdd, Math.mulDiv(priceLower, priceUpper, 1 << 96), 1 << 96);
        } else {
            amountToAdd = Math.mulDiv(Math.mulDiv(amountToAdd, 1 << 96, priceUpper), 1 << 96, priceLower);
        }

        _openPosition(amountToAdd, tickLower, tickUpper, fee);
    }

    /**
     * @notice Closes all Uniswap positions.
     * @dev This function closes all Uniswap positions, regardless of whether they are currently held in the treasure
     *      token or not.
     */
    function closePositionsAll() external onlyRole(MANAGER_ROLE) {
        _closePositionsAll();
    }

    /**
     * @notice Closes specific Uniswap LP positions whose market price has moved beyond the range in a favorable way
     *         such that the liquidity is fully held in the treasure token.
     * @dev For each position, if the market price (current tick) has moved outside the LP range towards the side where
     *      all liquidity is converted into the treasure token, those positions are closed. This ensures that we do not
     *      hold positions where liquidity is no longer actively earning fees.
     */
    function closePositionsWorkedOut() external onlyRole(MANAGER_ROLE) {
        bool changed;
        for (uint256 i = _tokenIds.length(); i > 0; i--) {
            uint256 tokenId = _tokenIds.at(i - 1);
            Position memory position = positions[tokenId];
            int24 currentTick = getCurrentTick(pools[position.fee]);

            if ((isToken0 && position.tickLower > currentTick) || (!isToken0 && position.tickUpper < currentTick)) {
                _closePosition(tokenId);
                changed = true;
            }
        }
        if (changed) _recalculateTicks();
    }

    /**
     * @notice Closes all Uniswap positions when the current market price moves adversely beyond a threshold.
     * @dev If the current market price is worse than the worst boundary of each LP range by a percentage defined by `tickDiff`,
     *      this function will close all open Uniswap positions. This mechanism is intended to protect against adverse market
     *      movements where maintaining the position would not earn fees effectively.
     */
    function closePositionsBadMarket() external onlyRole(MANAGER_ROLE) {
        int24 currentTick = TickMath.getTickAtSqrtRatio(_getOracleSqrtPriceX96());
        if ((isToken0 ? (currentTick - highestTick) : (lowestTick - currentTick)) > tickDiff) _closePositionsAll();
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function _deposit(uint256 assets) internal override {
        // we need to subtract incoming assets from the user
        uint256 currentPercentage = _getNettoPartForTokenReal(tokenTreasure, assets);
        if (address(tokenTreasure) == asset()) {
            _swap(isToken0, assets * (PRECISION - currentPercentage) / PRECISION);
        } else {
            _swap(!isToken0, assets * currentPercentage / PRECISION);
        }
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        uint256 amount0 = IERC20Metadata(token0).balanceOf(address(this)) * shares / totalSupply();
        uint256 amount1 = IERC20Metadata(token1).balanceOf(address(this)) * shares / totalSupply();

        uint256 farmingShares0 = IERC20Metadata(token0Vault).balanceOf(address(this)) * shares / totalSupply();
        uint256 farmingShares1 = IERC20Metadata(token1Vault).balanceOf(address(this)) * shares / totalSupply();

        if (farmingShares0 > 0) {
            amount0 += token0Vault.redeem(farmingShares0, address(this), address(this), 0);
        }

        if (farmingShares1 > 0) {
            amount1 += token1Vault.redeem(farmingShares1, address(this), address(this), 0);
        }

        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            (uint256 removed0, uint256 removed1) =
                _removeLiquidityAndRewardsPercent(_tokenIds.at(i), shares * PRECISION / totalSupply());

            amount0 += removed0;
            amount1 += removed1;
        }

        assets = asset() == address(token0) ? amount0 + _swap(false, amount1) : amount1 + _swap(true, amount0);
    }

    /**
     * @notice Calculates the percentage of the TVL represented by the token
     * subtracting the deposited amount from the total assets.
     * @return A percentage of the fund held in the particular token
     */
    function _getNettoPartForTokenReal(IERC20Metadata inAsset, uint256 depositedAmount)
        internal
        view
        returns (uint256)
    {
        (uint256 total0, uint256 total1) = getPositionAmounts();
        (uint256 amount0, uint256 amount1) = _getAmountsForFarmings();

        uint256 totalInRequested = (inAsset == token0 ? (amount0 + total0) : (amount1 + total1))
            + inAsset.balanceOf(address(this)) - (asset() == address(tokenTreasure) ? depositedAmount : 0);
        // we need to subtract deposited amount from the total assets
        uint256 totalAssets_ = totalAssets() - depositedAmount;
        return (totalAssets_ == 0)
            ? 0
            : _getInUnderlyingAsset(address(inAsset), totalInRequested) * PRECISION / totalAssets_;
    }

    /**
     * @notice Function to remove liquidity from a specific Dex position
     * @param tokenId The ID of the position to remove liquidity from
     * @param percent The percentage of liquidity to remove
     * @return amount0 The amount of token0 received from removing liquidity
     * @return amount1 The amount of token1 received from removing liquidity
     */
    function _removeLiquidityAndRewardsPercent(uint256 tokenId, uint256 percent)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 totalLiquidity = _getTokenLiquidity(tokenId);
        uint256 liquidity = totalLiquidity * percent / PRECISION;
        (uint256 liq0, uint256 liq1) = _decreaseLiquidity(tokenId, uint128(liquidity));
        (uint128 owed0, uint128 owed1) = _getTokensOwed(tokenId);

        // everything besides just claimed liquidity are fees
        uint256 fees0 = owed0 - liq0;
        uint256 fees1 = owed1 - liq1;
        (amount0, amount1) = _collect(
            tokenId,
            uint128(liquidity * fees0 / totalLiquidity + liq0),
            uint128(liquidity * fees1 / totalLiquidity + liq1)
        );
    }

    /**
     * @notice Function to decrease the liquidity of an existing Dex position
     * @param tokenId The ID of the position to decrease liquidity for
     * @param liquidity The amount of liquidity to remove from the position
     * @return amount0 The amount of token0 received from decreasing liquidity
     * @return amount1 The amount of token1 received from decreasing liquidity
     */
    function _decreaseLiquidity(uint256 tokenId, uint128 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        // Decrease liquidity for the current position and return the received token amounts
        (amount0, amount1) = positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max
            })
        );
    }

    /**
     * @notice Function to collect fees earned by the Dex position
     * @param tokenId The ID of the position to collect fees for
     * @param amount0Max The maximum amount of token0 to collect
     * @param amount1Max The maximum amount of token1 to collect
     * @return amount0 The amount of token0 collected
     * @return amount1 The amount of token1 collected
     */
    function _collect(uint256 tokenId, uint128 amount0Max, uint128 amount1Max)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        // Collect earned fees from the liquidity position
        (amount0, amount1) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: amount0Max,
                amount1Max: amount1Max
            })
        );
    }

    /**
     * @dev Calculates the square root of the price ratio between two tokens based on data from oracle.
     */
    function _getOracleSqrtPriceX96() internal view returns (uint160) {
        uint256 price0 = _getPrice(address(token0));
        uint256 price1 = _getPrice(address(token1));

        return uint160(
            Math.sqrt(Math.mulDiv(price0, 2 ** 96, price1))
                * Math.sqrt(Math.mulDiv(10 ** token1Decimals, 2 ** 96, 10 ** token0Decimals))
        );
    }

    /**
     * @notice Retrieves and stores a pool for a particular fee tier.
     * @param fee Fee tier to retrieve
     * @return pool Address of the pool
     */
    function _getOrUpdatePool(uint24 fee) internal returns (address pool) {
        pool = pools[fee];
        if (pool == address(0)) {
            pool = IUniswapV3Factory(positionManager.factory()).getPool(address(token0), address(token1), fee);
            pools[fee] = pool;
            feeAmountTickSpacing[fee] = IUniswapV3Pool(pool).tickSpacing();
        }
    }

    /**
     * @notice Internal function to perform a token swap on the DEX
     * @param zeroForOne Whether to swap token0 for token1 (true) or token1 for token0 (false)
     * @param amount The amount of tokens to swap
     * @return amountOut The amount of tokens received from the swap
     */
    function _swap(bool zeroForOne, uint256 amount) internal returns (uint256 amountOut) {
        // Execute the swap and capture the output amount
        if (amount == 0) return 0;
        (int256 amount0, int256 amount1) = IUniswapV3Pool(_getOrUpdatePool(feeForSwaps)).swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            zeroForOne ? abi.encode(token0, token1) : abi.encode(token1, token0)
        );

        // Return the output amount (convert from negative if needed)
        amountOut = uint256(-(zeroForOne ? amount1 : amount0));
        _checkSlippage(zeroForOne, amount, amountOut);
    }

    /**
     * @notice Rounds desired price boundaries to the nearest permissible Uniswap ticks based on tick spacing.
     * @dev Adjusts price boundaries upwards when buying token0, and downwards otherwise. This ensures
     *      valid tick boundaries for given price ranges in Uniswap.
     *
     * @param priceLower The initial price boundary (lower bound).
     * @param priceUpper The final price boundary (upper bound).
     * @param tickSpacing The allowable spacing between ticks.
     * @return tickLower The lower tick
     * @return tickUpper The upper tick
     */
    function _adjustTicks(uint160 priceLower, uint160 priceUpper, int24 tickSpacing)
        internal
        view
        returns (int24 tickLower, int24 tickUpper)
    {
        tickLower = TickMath.getTickAtSqrtRatio(priceLower);
        tickUpper = TickMath.getTickAtSqrtRatio(priceUpper);
        if (isToken0) {
            tickLower -= (tickLower < 0 ? tickSpacing : int24(0)) + tickLower % tickSpacing;
            tickUpper -= (tickUpper < 0 ? tickSpacing : int24(0)) + tickUpper % tickSpacing;
        } else {
            tickLower -= tickLower < 0 ? tickLower % tickSpacing : (tickLower % tickSpacing - tickSpacing);
            tickUpper -= tickUpper < 0 ? tickUpper % tickSpacing : (tickUpper % tickSpacing - tickSpacing);
        }
    }

    /**
     * @notice Gets the latest price for a asset using oracle
     * @param asset_ The address of the asset
     * @return The latest price from the oracle
     */
    function _getPrice(address asset_) internal view returns (uint256) {
        IChainlinkOracle oracle = oracles[asset_];
        (uint80 roundID, int256 price,, uint256 timestamp, uint80 answeredInRound) = oracle.latestRoundData();

        require(answeredInRound >= roundID, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink price reporting 0");

        // returns price in the vault decimals
        return uint256(price) * (10 ** decimals()) / (10 ** oracle.decimals());
    }

    /**
     * @notice Converts an amount to the vault's underlying asset value
     * @param asset_ The address of the asset to convert from
     * @param amount The amount to convert
     * @return The equivalent amount in the vault's underlying asset
     */
    function _getInUnderlyingAsset(address asset_, uint256 amount) internal view returns (uint256) {
        return _convert(asset_, asset(), amount);
    }

    /**
     * @notice Converts an amount of the assetIn to the assetOut
     * @param assetIn The address of the asset to convert from
     * @param assetOut The address of the asset to convert to
     * @param amount The amount to convert
     * @return The equivalent amount in the assetOut
     */
    function _convert(address assetIn, address assetOut, uint256 amount) internal view returns (uint256) {
        if (assetIn != assetOut) {
            return (amount * _getPrice(assetIn) / (10 ** IERC20Metadata(assetIn).decimals()))
                * (10 ** IERC20Metadata(assetOut).decimals()) / _getPrice(assetOut);
        }
        return amount;
    }

    /**
     * @notice Creates a new Uniswap LP position using the specified amount of tokens and price range.
     * @dev This function is internal and is called by `openPositionIfNeed` to initialize an LP position
     *      once it's determined that additional LP positions are needed to acquire more treasure tokens.
     *
     * @param amount The amount of free tokens intended for exchange into the treasure token.
     * @param tickLower The lower tick for position
     * @param tickUpper The upper tick for position
     * @param fee_ The fee tier for the Uniswap V3 pool position.
     */
    function _openPosition(uint256 amount, int24 tickLower, int24 tickUpper, uint24 fee_) internal {
        if (isToken0) {
            uint256 balance = token1.balanceOf(address(this));
            if (balance < amount) {
                amount = balance
                    + token1Vault.redeem(
                        (amount - balance) * 10 ** token1Decimals / token1Vault.sharePrice(),
                        address(this),
                        address(this),
                        0
                    );
                // may raise error if amount > funds of the vault in the farming
            }
        } else {
            uint256 balance = token0.balanceOf(address(this));
            if (balance < amount) {
                amount = balance
                    + token0Vault.redeem(
                        (amount - balance) * 10 ** token0Decimals / token0Vault.sharePrice(),
                        address(this),
                        address(this),
                        0
                    );
                // may raise error if amount > funds of the vault in the farming
            }
        }

        (uint256 amount0Desired, uint256 amount1Desired) = isToken0 ? (uint256(0), amount) : (amount, 0);

        (uint256 tokenId,,,) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: fee_,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        _tokenIds.add(tokenId);

        positions[tokenId] = Position({tickLower: tickLower, tickUpper: tickUpper, fee: fee_});
    }

    /**
     * @dev Closes all Uniswap positions.
     */
    function _closePositionsAll() internal {
        for (uint256 i = _tokenIds.length(); i > 0; i--) {
            uint256 tokenId = _tokenIds.at(i - 1);
            _closePosition(tokenId);
        }
        _recalculateTicks();
    }

    /**
     * @dev Recalculates the lowest and highest ticks for current positions.
     */
    function _recalculateTicks() internal {
        lowestTick = TickMath.MAX_TICK;
        highestTick = TickMath.MIN_TICK;
        if (_tokenIds.length() == 0) return;
        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            Position memory position = positions[_tokenIds.at(i)];
            if (position.tickUpper > highestTick) highestTick = position.tickUpper;
            if (position.tickLower < lowestTick) lowestTick = position.tickLower;
        }
    }

    /**
     * @dev Closes a specific position.
     * @param tokenId Token ID of the position to close
     */
    function _closePosition(uint256 tokenId) internal {
        uint128 liquidity = _getTokenLiquidity(tokenId);

        _decreaseLiquidity(tokenId, liquidity);
        _collect(tokenId, type(uint128).max, type(uint128).max);

        positionManager.burn(tokenId);
        _tokenIds.remove(tokenId);
        delete positions[tokenId];
    }

    /**
     * @dev Retrieves the amounts of tokens owed to the vault from the farming positions.
     * @return amount0 The amount of token0 owed
     * @return amount1 The amount of token1 owed
     */
    function _getAmountsForFarmings() internal view returns (uint256 amount0, uint256 amount1) {
        amount0 = token0Vault.getBalanceInUnderlying(address(this));
        amount1 = token1Vault.getBalanceInUnderlying(address(this));
    }

    /**
     * @dev Retrieves the amounts of tokens owed to the vault from all uniswap positions.
     * @return amount0 The amount of token0 owed
     * @return amount1 The amount of token1 owed
     */
    function _getTokensOwedForAllPositions() internal view returns (uint128 amount0, uint128 amount1) {
        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            (uint128 amount0_, uint128 amount1_) = _getTokensOwed(_tokenIds.at(i));
            amount0 += amount0_;
            amount1 += amount1_;
        }
    }

    /**
     * @dev Retrieves the amounts of tokens owed to the vault from a specific uniswap position.
     * @param tokenId Token ID of the position
     * @return amount0 The amount of token0 owed
     * @return amount1 The amount of token1 owed
     */
    function _getTokensOwed(uint256 tokenId) internal view virtual returns (uint128 amount0, uint128 amount1) {
        (,,,,,,,,,, amount0, amount1) = positionManager.positions(tokenId);
    }

    /**
     * @dev Retrieves the liquidity of a specific uniswap position.
     * @param tokenId Token ID of the position
     * @return liquidity The liquidity of the position
     */
    function _getTokenLiquidity(uint256 tokenId) internal view virtual returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = positionManager.positions(tokenId);
    }

    /**
     * @notice Checks if the swap was within the allowed slippage
     * @param zeroForOne Whether the swap is zero for one or not
     * @param amountIn The initial amount of tokens swapped
     * @param amountOut The amount of tokens received
     *
     * Ensures that the price impact of the swap doesn't exceed the permitted slippage.
     */
    function _checkSlippage(bool zeroForOne, uint256 amountIn, uint256 amountOut) internal view {
        (address from, address to) =
            zeroForOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        uint256 amountInUsd = amountIn * _getPrice(from) / (10 ** IERC20Metadata(from).decimals());
        uint256 amountOutUsd = amountOut * _getPrice(to) / (10 ** IERC20Metadata(to).decimals());
        require(
            amountOutUsd >= amountInUsd * (slippagePrecision - maxSlippage) / slippagePrecision,
            "SeasonalVault: Slippage"
        );
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address token) internal virtual override(BaseVault) returns (bool) {
        return token != address(token0) && token != address(token1) && token != address(token0Vault)
            && token != address(token1Vault);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Uniswap V3 swap callback for providing required token amounts during swaps
     * @param amount0Delta Amount of the first token delta
     * @param amount1Delta Amount of the second token delta
     * @param data Encoded data containing swap details
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Ensure the callback is being called by the correct pool
        require(amount0Delta > 0 || amount1Delta > 0);
        require(msg.sender == pools[feeForSwaps]);

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
