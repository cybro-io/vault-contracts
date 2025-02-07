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
 * @title SeasonalCryptoVault
 * @notice Vault that manages assets based on crypto market seasons strategy
 * @dev Implements seasonal strategy for crypto asset management
 */
contract SeasonalCryptoVault is BaseVault, IUniswapV3SwapCallback, IERC721Receiver {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.UintSet;

    struct Position {
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
    }

    IERC20Metadata tokenCrypto;
    IERC20Metadata tokenStable;
    IERC20Metadata tokenTreasure;
    IVault public stableVault;
    IVault public cryptoVault;

    INonfungiblePositionManager positionManager;

    EnumerableSet.UintSet tokenIds;
    mapping(uint256 => Position) positions;
    int24 public tickSpacing;
    uint256 public constant PRECISION = 1e24;

    bool public immutable stableTokenIsToken0;
    int24 lowestTick;

    mapping(uint24 fee => address pool) public pools;
    mapping(address token => IChainlinkOracle oracle) public oracles;

    constructor(
        address payable _positionManager,
        IERC20Metadata _asset,
        IERC20Metadata _tokenCrypto,
        IERC20Metadata _tokenStable,
        IFeeProvider _feeProvider,
        address _feeRecipient
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        positionManager = INonfungiblePositionManager(_positionManager);
        tokenCrypto = _tokenCrypto;
        tokenStable = _tokenStable;
        stableTokenIsToken0 = tokenStable < _tokenCrypto;
        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        IERC20Metadata(tokenCrypto).forceApprove(address(positionManager), type(uint256).max);
        IERC20Metadata(tokenStable).forceApprove(address(positionManager), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256 total) {
        (uint256 total0, uint256 total1) = getPositionAmounts();
        (uint256 amountStable, uint256 amountCrypto) = _getAmountsForFarmings();
        // returns total assets in asset token
        if (stableTokenIsToken0) {
            return _getInUnderlyingAsset(
                address(tokenStable), total0 + tokenStable.balanceOf(address(this)) + amountStable
            )
                + _getInUnderlyingAsset(address(tokenCrypto), total1 + tokenCrypto.balanceOf(address(this)) + amountCrypto);
        }

        return _getInUnderlyingAsset(address(tokenCrypto), total0 + tokenCrypto.balanceOf(address(this)) + amountCrypto)
            + _getInUnderlyingAsset(address(tokenStable), total1 + tokenStable.balanceOf(address(this)) + amountStable);
    }

    function _getAmountsForFarmings() internal view returns (uint256 amountStable, uint256 amountCrypto) {
        amountStable = stableVault.getBalanceInUnderlying(address(this));
        amountCrypto = cryptoVault.getBalanceInUnderlying(address(this));
    }

    function setOracles(address[] calldata oracles_, address[] calldata tokens_) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < oracles_.length; i++) {
            oracles[tokens_[i]] = IChainlinkOracle(oracles_[i]);
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

    /// @inheritdoc BaseVault
    function underlyingTVL() external view virtual override returns (uint256) {
        //
    }

    /// @inheritdoc BaseVault
    function _deposit(uint256 assets) internal override {}

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        uint256 neededAssets = shares * totalAssets() / totalSupply();
        if (IERC20Metadata(asset()).balanceOf(address(this)) < neededAssets) {
            (uint256 amountStable, uint256 amountCrypto) = _getAmountsForFarmings();
            // withdraw from farmings?
            // close lp positions?
        }
    }

    function getPositionAmounts() public view returns (uint256 amount0, uint256 amount1) {
        (uint128 owed0, uint128 owed1) = _getTokensOwedForAllPositions();
        (amount0, amount1) = _getAmountsForLiquidityForAll();
        amount0 += owed0;
        amount1 += owed1;
    }

    function _getAmountsForLiquidityForAll() internal view returns (uint256 amount0, uint256 amount1) {
        for (uint256 i = 0; i < tokenIds.length(); i++) {
            uint256 tokenId = tokenIds.at(i);
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
        for (uint256 i = 0; i < tokenIds.length(); i++) {
            (uint128 amount0_, uint128 amount1_) = _getTokensOwed(tokenIds.at(i));
            amount0 += amount0_;
            amount1 += amount1_;
        }
    }

    function _getTokensOwed(uint256 tokenId) internal view virtual returns (uint128 amount0, uint128 amount1) {
        (,,,,,,,,,, amount0, amount1) = positionManager.positions(tokenId);
    }

    function setTreasureToken(address _token) external onlyRole(MANAGER_ROLE) {
        tokenTreasure = IERC20Metadata(_token);
    }

    // only role manager role
    function investFreeMoney() external {
        cryptoVault.deposit(IERC20Metadata(tokenCrypto).balanceOf(address(this)), address(this), 0);
        stableVault.deposit(IERC20Metadata(tokenStable).balanceOf(address(this)), address(this), 0);
    }

    function _getAndUpdatePool(uint24 fee) internal returns (address pool) {
        pool = pools[fee];
        if (pool == address(0)) {
            pool = IUniswapV3Factory(positionManager.factory()).getPool(address(tokenCrypto), address(tokenStable), fee);
            pools[fee] = pool;
        }
    }

    // function _getPoolForDeposit

    // function _swap(bool zeroForOne, uint256 amount) internal override returns (uint256) {
    //     // Execute the swap and capture the output amount
    //     (int256 amount0, int256 amount1) = pool.swap(
    //         address(this),
    //         zeroForOne,
    //         int256(amount),
    //         zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
    //         abi.encode(token0, token1)
    //     );

    //     // Return the output amount (convert from negative if needed)
    //     return uint256(-(zeroForOne ? amount1 : amount0));
    // }

    // function withdrawFromFarming(uint256 amount) external {

    // }

    // onlyRole(MANAGER_ROLE)
    function claimDEX() external {
        // Collect earned fees from the liquidity position
        for (uint256 i = 0; i < tokenIds.length(); i++) {
            positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenIds.at(i),
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }
    }

    function getNettoPartForTokenOptimistic() public view returns (uint256) {
        uint256 totalPart = tokenTreasure.balanceOf(address(this));
        (uint256 total0, uint256 total1) = getPositionAmounts();
        uint256 priceStable = _getPrice(address(tokenStable));
        uint256 priceCrypto = _getPrice(address(tokenCrypto));
        if (stableTokenIsToken0) {
            total0 = priceStable * total0 / 10 ** tokenStable.decimals();
            total1 = priceCrypto * total1 / 10 ** tokenCrypto.decimals();
        } else {
            total0 = priceCrypto * total0 / 10 ** tokenCrypto.decimals();
            total1 = priceStable * total1 / 10 ** tokenStable.decimals();
        }
        if (tokenTreasure == tokenCrypto) {
            totalPart = (totalPart + cryptoVault.getBalanceInUnderlying(address(this))) * priceCrypto
                / 10 ** tokenCrypto.decimals();
        } else {
            totalPart = (totalPart + stableVault.getBalanceInUnderlying(address(this))) * priceStable
                / 10 ** tokenStable.decimals();
        }
        return totalPart * PRECISION / totalAssets();
    }

    function openPositionIfNeed(uint256 percentageTreasureDesired_, uint256 price1, uint256 price2, uint24 fee)
        external
    {
        // require(fee <= MAX_FEE, "Fee too high");

        uint256 currentPercentage = getNettoPartForTokenOptimistic();
        if (percentageTreasureDesired_ <= currentPercentage) return;

        uint256 amountToAdd = totalAssets() * percentageTreasureDesired_ / PRECISION;

        uint256 currentPrice = getCurrentSqrtPrice(_getAndUpdatePool(fee));

        bool isToken0 = (tokenTreasure == tokenCrypto) ? !stableTokenIsToken0 : stableTokenIsToken0;
        if ((isToken0 && currentPrice < price1) || (!isToken0 && currentPrice > price1)) {
            price2 = isToken0 ? price2 - (price1 - currentPrice) : price2 + (currentPrice - price1);
            price1 = currentPrice;
        }

        // мы должны получать цену всегда >= выставленных цен
        (int24 tickWorse, int24 tickBetter) = _getGreatestTicks(price1, price2);

        _openPosition(amountToAdd, tickWorse, tickBetter, fee);
    }

    function _getGreatestTicks(uint256 price1, uint256 price2) internal view returns (int24 tick1, int24 tick2) {
        tick1 = TickMath.getTickAtSqrtRatio(uint160(price1));
        tick2 = TickMath.getTickAtSqrtRatio(uint160(price2));
        tick1 % tickSpacing == 0 ? tick1 : tick1 = tick1 + tickSpacing - tick1 % tickSpacing;
        tick2 % tickSpacing == 0 ? tick2 : tick2 = tick2 + tickSpacing - tick2 % tickSpacing;
        // tick1 must nbe tickLower and tick2 must be tickUpper
        if (tick1 > tick2) {
            (tick1, tick2) = (tick2, tick1);
        }
    }

    function _openPosition(uint256 amount, int24 tickWorse, int24 tickBetter, uint24 fee_) internal {
        // open position
        // if free money is lower then amount
        if (tokenTreasure == tokenCrypto) {
            if (tokenStable.balanceOf(address(this)) < amount) {
                // withdraw from farming
                // должны ли мы учитывать комиссию?
                stableVault.redeem(
                    amount * 10 ** stableVault.decimals() / stableVault.sharePrice(), address(this), address(this), 0
                );
            }
        } else {
            if (tokenCrypto.balanceOf(address(this)) < amount) {
                // withdraw from farming
                // if (cryptoVault.getWithdrawalFee() > 0) {
                cryptoVault.redeem(
                    amount * 10 ** cryptoVault.decimals() / cryptoVault.sharePrice(), address(this), address(this), 0
                );
            }
        }

        bool isAmount0 = (tokenTreasure == tokenCrypto) == stableTokenIsToken0;
        uint256 amount0Desired = isAmount0 ? amount : 0;
        uint256 amount1Desired = isAmount0 ? 0 : amount;
        (address token0, address token1) = stableTokenIsToken0
            ? (address(tokenStable), address(tokenCrypto))
            : (address(tokenCrypto), address(tokenStable));

        (uint256 tokenId,,,) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
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

        tokenIds.add(tokenId);

        positions[tokenId] = Position({tickLower: tickWorse, tickUpper: tickBetter, fee: fee_});
    }

    function closePositionsAll() external onlyRole(MANAGER_ROLE) {
        for (uint256 i = tokenIds.length(); i > 0; i--) {
            uint256 tokenId = tokenIds.at(i - 1);
            _closePosition(tokenId);
            tokenIds.remove(tokenId);
            delete positions[tokenId];
        }
    }

    function closePositionsWorkedOut() external onlyRole(MANAGER_ROLE) {
        bool isToken0 = (tokenTreasure == tokenCrypto) ? !stableTokenIsToken0 : stableTokenIsToken0;
        for (uint256 i = tokenIds.length(); i > 0; i--) {
            uint256 tokenId = tokenIds.at(i - 1);
            Position memory position = positions[tokenId];
            int24 currentTick = getCurrentTick(pools[position.fee]);

            if ((isToken0 && position.tickLower < currentTick) || (!isToken0 && position.tickUpper > currentTick)) {
                _closePosition(tokenId);
                tokenIds.remove(tokenId);
                delete positions[tokenId];
            }
        }
    }

    // function closePositionsBadMarket() external onlyRole(MANAGER_ROLE) {
    //     we need to handle lowest tick of all positions
    //     for (uint256 i = 0; i < positions.length; i++) {
    //         // }
    //     }
    // }

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

    function _getTokenLiquidity(uint256 tokenId) internal view virtual returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = positionManager.positions(tokenId);
    }

    function getCurrentTick(address pool) public view returns (int24 tick) {
        (, tick,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    function getCurrentSqrtPrice(address pool) public view returns (uint256 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        return uint256(sqrtPriceX96);
    }

    function _validateTokenToRecover(address token) internal virtual override(BaseVault) returns (bool) {
        return token != address(tokenCrypto) && token != address(tokenStable) && token != address(stableVault)
            && token != address(cryptoVault);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Ensure the callback is being called by the correct pool
        require(amount0Delta > 0 || amount1Delta > 0);
        // require(msg.sender == address(pool));

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
