// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseVault} from "./BaseVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
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

    /* ========== IMMUTABLE VARIABLES ========== */

    IERC20Metadata public immutable token0;
    IERC20Metadata public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;

    // maybe we need opportunity for update vaults?
    IVault public immutable token0Vault;
    IVault public immutable token1Vault;

    INonfungiblePositionManager public immutable positionManager;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    EnumerableSet.UintSet _tokenIds;
    mapping(uint256 => Position) positions;
    IERC20Metadata public tokenTreasure;
    int24 public worstTick;

    mapping(uint24 fee => address pool) public pools;
    mapping(uint24 => int24) public feeAmountTickSpacing;
    mapping(address token => IChainlinkOracle oracle) public oracles;

    uint24 public feeForSwaps;
    bool public isToken0;

    /* ========== CONSTRUCTOR ========== */

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

    function getPositionAmounts() public view returns (uint256 amount0, uint256 amount1) {
        (uint128 owed0, uint128 owed1) = _getTokensOwedForAllPositions();
        (amount0, amount1) = _getAmountsForLiquidityForAll();
        amount0 += owed0;
        amount1 += owed1;
    }

    function getNettoPartForTokenOptimistic() public view returns (uint256) {
        uint256 totalPart = tokenTreasure.balanceOf(address(this));
        (uint256 total0, uint256 total1) = getPositionAmounts();
        (uint256 amount0, uint256 amount1) = _getAmountsForFarmings();
        uint256 totalAssets_;

        if (isToken0) {
            totalPart = _getInUnderlyingAsset(address(token0), (totalPart + amount0 + total0))
                + _getInUnderlyingAsset(address(token1), total1);
            totalAssets_ = totalPart + _getInUnderlyingAsset(address(token1), amount1 + token1.balanceOf(address(this)));
        } else {
            totalPart = _getInUnderlyingAsset(address(token1), (totalPart + amount1 + total1))
                + _getInUnderlyingAsset(address(token0), total0);
            totalAssets_ = totalPart + _getInUnderlyingAsset(address(token0), amount0 + token0.balanceOf(address(this)));
        }

        return totalPart * PRECISION / totalAssets_;
    }

    function getNettoPartForTokenReal() public view returns (uint256) {}

    function getNettoTVL() public view returns (uint256) {}

    function getCurrentTick(address pool) public view returns (int24 tick) {
        (, tick,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    function getCurrentSqrtPrice(address pool) public view returns (uint256 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        return uint256(sqrtPriceX96);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function setTreasureToken(address token_) external onlyRole(MANAGER_ROLE) {
        require(token_ == address(token0) || token_ == address(token1), "Invalid token");
        tokenTreasure = IERC20Metadata(token_);
        isToken0 = tokenTreasure == token0;
        _recalculateWorstTick();
    }

    function setFeeForSwaps(uint24 fee_) external onlyRole(MANAGER_ROLE) {
        feeForSwaps = fee_;
    }

    function setOracles(address[] calldata tokens_, IChainlinkOracle[] calldata oracles_)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < oracles_.length; i++) {
            oracles[tokens_[i]] = IChainlinkOracle(oracles_[i]);
        }
    }

    function updatePoolForFee(uint24 fee) external onlyRole(MANAGER_ROLE) returns (address pool) {
        pool = IUniswapV3Factory(positionManager.factory()).getPool(address(token0), address(token1), fee);
        pools[fee] = pool;
        feeAmountTickSpacing[fee] = IUniswapV3Pool(pool).tickSpacing();
    }

    function investFreeMoney() external onlyRole(MANAGER_ROLE) {
        token0Vault.deposit(token0.balanceOf(address(this)), address(this), 0);
        token1Vault.deposit(token1.balanceOf(address(this)), address(this), 0);
    }

    function claimDEX() external onlyRole(MANAGER_ROLE) {
        // Collect earned fees from the liquidity position
        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: _tokenIds.at(i),
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }
    }

    function openPositionIfNeed(uint256 percentageTreasureDesired_, uint256 price1, uint256 price2, uint24 fee)
        external
    {
        uint256 currentPercentage = getNettoPartForTokenOptimistic();
        if (percentageTreasureDesired_ <= currentPercentage) return;

        uint256 amountToAdd = totalAssets() * (percentageTreasureDesired_ - currentPercentage) / PRECISION;
        uint256 currentPrice = getCurrentSqrtPrice(_getOrUpdatePool(fee));
        if (price1 > price2) (price1, price2) = (price2, price1);

        if ((isToken0 && currentPrice < price2)) {
            price1 -= (price2 - currentPrice);
            price2 = currentPrice;
        } else if (!isToken0 && currentPrice > price1) {
            price2 += (currentPrice - price1);
            price1 = currentPrice;
        }

        (int24 tickWorse, int24 tickBetter) = _getGreatestTicks(price1, price2, feeAmountTickSpacing[fee]);

        if (isToken0) {
            // max
            worstTick = tickBetter < worstTick ? worstTick : tickBetter;
        } else {
            // min
            worstTick = tickWorse > worstTick ? worstTick : tickWorse;
        }

        _openPosition(amountToAdd, tickWorse, tickBetter, fee);
    }

    function closePositionsAll() external onlyRole(MANAGER_ROLE) {
        _closePositionsAll();
    }

    function closePositionsWorkedOut() external onlyRole(MANAGER_ROLE) {
        bool changed;
        for (uint256 i = _tokenIds.length(); i > 0; i--) {
            uint256 tokenId = _tokenIds.at(i - 1);
            Position memory position = positions[tokenId];
            int24 currentTick = getCurrentTick(pools[position.fee]);

            if ((isToken0 && position.tickLower > currentTick) || (!isToken0 && position.tickUpper < currentTick)) {
                _closePosition(tokenId);
                _tokenIds.remove(tokenId);
                delete positions[tokenId];
                changed = true;
            }
        }
        if (changed) _recalculateWorstTick();
    }

    function closePositionsBadMarket() external onlyRole(MANAGER_ROLE) {
        uint256 currentPrice = getCurrentSqrtPrice(pools[feeForSwaps]) ** 2;
        uint256 worstPrice = uint256(TickMath.getSqrtRatioAtTick(worstTick)) ** 2;
        if (isToken0) {
            if (Math.mulDiv(currentPrice, PRECISION, worstPrice) > 12e23) {
                // prec + proc
                _closePositionsAll();
            }
        } else {
            if (Math.mulDiv(currentPrice, PRECISION, worstPrice) < 8e23) {
                // prec - proc
                _closePositionsAll();
            }
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function _deposit(uint256 assets) internal override {
        // we need to subtract incoming assets from the user
        uint256 currentPercentage = getNettoPartForTokenOptimistic();
        if (address(tokenTreasure) == asset()) {
            _swap(isToken0, assets * (PRECISION - currentPercentage) / PRECISION);
        } else {
            _swap(!isToken0, assets * currentPercentage / PRECISION);
        }
        // check slippage?
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * totalAssets() / totalSupply();
        // uint256 balance = IERC20Metadata(asset()).balanceOf(address(this));
        // if (balance < assets) {
        //     (uint256 amountStable, uint256 amountCrypto) = _getAmountsForFarmings();
        //     // withdraw from all of the stuff: free, farmings, lp positions
        // }
    }

    function _swap(bool zeroForOne, uint256 amount) internal returns (uint256) {
        // Execute the swap and capture the output amount
        (int256 amount0, int256 amount1) = IUniswapV3Pool(_getOrUpdatePool(feeForSwaps)).swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            zeroForOne ? abi.encode(token0, token1) : abi.encode(token1, token0)
        );

        // Return the output amount (convert from negative if needed)
        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    function _getOrUpdatePool(uint24 fee) internal returns (address pool) {
        pool = pools[fee];
        if (pool == address(0)) {
            pool = IUniswapV3Factory(positionManager.factory()).getPool(address(token0), address(token1), fee);
            pools[fee] = pool;
            feeAmountTickSpacing[fee] = IUniswapV3Pool(pool).tickSpacing();
        }
    }

    function _getGreatestTicks(uint256 price1, uint256 price2, int24 tickSpacing)
        internal
        view
        returns (int24 tick1, int24 tick2)
    {
        // price2 must be greater than price1
        // if we buy token 0 ticks must rounding down
        // if we buy token 1 ticks must rounding up
        tick1 = TickMath.getTickAtSqrtRatio(uint160(price1));
        tick2 = TickMath.getTickAtSqrtRatio(uint160(price2));
        if (isToken0) {
            tick1 -= tick1 < 0 ? tickSpacing : 0 + tick1 % tickSpacing;
            tick2 -= tick2 < 0 ? tickSpacing : 0 + tick2 % tickSpacing;
        } else {
            tick1 -= tick1 < 0 ? tick1 % tickSpacing : (tick1 % tickSpacing - tickSpacing);
            tick2 -= tick2 < 0 ? tick2 % tickSpacing : (tick2 % tickSpacing - tickSpacing);
        }
    }

    function _getPrice(address asset_) internal view returns (uint256) {
        IChainlinkOracle oracle = oracles[asset_];
        (uint80 roundID, int256 price,, uint256 timestamp, uint80 answeredInRound) = oracle.latestRoundData();

        require(answeredInRound >= roundID, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink price reporting 0");

        // returns price in the vault decimals
        return uint256(price) * (10 ** decimals()) / 10 ** (oracle.decimals());
    }

    function _getInUnderlyingAsset(address asset_, uint256 amount) internal view returns (uint256) {
        if (asset_ != asset()) {
            return (amount * _getPrice(asset_) / (10 ** IERC20Metadata(asset_).decimals())) * (10 ** decimals())
                / _getPrice(asset());
        }
        return amount;
    }

    function _openPosition(uint256 amount, int24 tickWorse, int24 tickBetter, uint24 fee_) internal {
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
                // may raise error if amount > funds of the vault int he farming
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
                // may raise error if amount > funds of the vault int he farming
            }
        }

        (uint256 amount0Desired, uint256 amount1Desired) = isToken0 ? (uint256(0), amount) : (amount, 0);

        (uint256 tokenId,,,) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(token0),
                token1: address(token1),
                fee: fee_,
                tickLower: tickWorse,
                tickUpper: tickBetter,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        _tokenIds.add(tokenId);

        positions[tokenId] = Position({tickLower: tickWorse, tickUpper: tickBetter, fee: fee_});
    }

    function _closePositionsAll() internal {
        for (uint256 i = _tokenIds.length(); i > 0; i--) {
            uint256 tokenId = _tokenIds.at(i - 1);
            _closePosition(tokenId);
            _tokenIds.remove(tokenId);
            delete positions[tokenId];
        }
        _recalculateWorstTick();
    }

    function _recalculateWorstTick() internal {
        worstTick = isToken0 ? TickMath.MIN_TICK : TickMath.MAX_TICK;
        if (_tokenIds.length() == 0) return;
        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            uint256 tokenId = _tokenIds.at(i);
            Position memory position = positions[tokenId];
            if (isToken0) {
                worstTick = position.tickUpper > worstTick ? position.tickUpper : worstTick;
            } else {
                worstTick = position.tickLower < worstTick ? position.tickLower : worstTick;
            }
        }
    }

    function _closePosition(uint256 tokenId) internal {
        uint128 liquidity = _getTokenLiquidity(tokenId);
        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: type(uint256).max
            })
        );

        positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
        positionManager.burn(tokenId);
    }

    function _getAmountsForFarmings() internal view returns (uint256 amount0, uint256 amount1) {
        amount0 = token0Vault.getBalanceInUnderlying(address(this));
        amount1 = token1Vault.getBalanceInUnderlying(address(this));
    }

    function _getAmountsForLiquidityForAll() internal view returns (uint256 amount0, uint256 amount1) {
        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            uint256 tokenId = _tokenIds.at(i);
            Position memory position = positions[tokenId];
            uint160 sqrtRatioX96 = uint160(getCurrentSqrtPrice(pools[position.fee]));
            uint128 liquidity = _getTokenLiquidity(tokenId);
            (uint256 amount0_, uint256 amount1_) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(position.tickLower),
                TickMath.getSqrtRatioAtTick(position.tickUpper),
                liquidity
            );
            amount0 += amount0_;
            amount1 += amount1_;
        }
    }

    function _getTokensOwedForAllPositions() internal view returns (uint128 amount0, uint128 amount1) {
        for (uint256 i = 0; i < _tokenIds.length(); i++) {
            (uint128 amount0_, uint128 amount1_) = _getTokensOwed(_tokenIds.at(i));
            amount0 += amount0_;
            amount1 += amount1_;
        }
    }

    function _getTokensOwed(uint256 tokenId) internal view virtual returns (uint128 amount0, uint128 amount1) {
        (,,,,,,,,,, amount0, amount1) = positionManager.positions(tokenId);
    }

    function _getTokenLiquidity(uint256 tokenId) internal view virtual returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = positionManager.positions(tokenId);
    }

    function _validateTokenToRecover(address token) internal virtual override(BaseVault) returns (bool) {
        return token != address(token0) && token != address(token1) && token != address(token0Vault)
            && token != address(token1Vault);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

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
