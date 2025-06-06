// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

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
import {OracleData} from "./libraries/OracleData.sol";

library Constants {
    /// @notice The precision used for calculations involving percentages
    uint256 constant PRECISION = 1e24;
    /// @notice The precision used for slippage calculations
    uint32 constant SLIPPAGE_PRECISION = 10000;
}

library PositionsLogic {
    using EnumerableSet for EnumerableSet.UintSet;

    struct Position {
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
    }

    struct Positions {
        /// @notice Mapping of token IDs to Uniswap positions
        mapping(uint256 tokenId => Position position) positions;
        /// @notice Set of token IDs for managed Uniswap positions
        EnumerableSet.UintSet tokenIds;
        /// @notice The lowest tick of all current positions
        int24 lowestTick;
        /// @notice The highest tick of all current positions
        int24 highestTick;
    }

    /**
     * @dev Recalculates the lowest and highest ticks for current positions.
     */
    function recalculateTicks(Positions storage self) public {
        self.lowestTick = TickMath.MAX_TICK;
        self.highestTick = TickMath.MIN_TICK;
        if (self.tokenIds.length() == 0) return;
        for (uint256 i = 0; i < self.tokenIds.length(); i++) {
            PositionsLogic.Position memory position = self.positions[self.tokenIds.at(i)];
            if (position.tickUpper > self.highestTick) self.highestTick = position.tickUpper;
            if (position.tickLower < self.lowestTick) self.lowestTick = position.tickLower;
        }
    }

    /**
     * @dev Adds a new position to the set.
     */
    function add(Positions storage self, uint256 tokenId, Position memory position) external {
        self.positions[tokenId] = position;
        self.tokenIds.add(tokenId);

        if (position.tickUpper > self.highestTick) self.highestTick = position.tickUpper;
        if (position.tickLower < self.lowestTick) self.lowestTick = position.tickLower;
    }

    /**
     * @notice Closes a position at a given index.
     * @param positionManager The address of the Uniswap V3 position manager
     * @param id The index of the position to close
     */
    function closeAt(Positions storage self, INonfungiblePositionManager positionManager, uint256 id) external {
        close(self, positionManager, self.tokenIds.at(id));
    }

    /**
     * @notice Closes a position by burning it and removing liquidity.
     * @param positionManager The address of the Uniswap V3 position manager
     * @param tokenId The ID of the position to close
     */
    function close(Positions storage self, INonfungiblePositionManager positionManager, uint256 tokenId) public {
        (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);

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

        self.tokenIds.remove(tokenId);
        delete self.positions[tokenId];
    }

    /**
     * @notice Removes liquidity from all positions and claims rewards.
     * @param positionManager The address of the Uniswap V3 position manager
     * @param percent The percentage of liquidity to remove
     * @return amount0 The amount of token0 claimed
     * @return amount1 The amount of token1 claimed
     */
    function removeLiquidityAndRewardsPercent(
        Positions storage self,
        INonfungiblePositionManager positionManager,
        uint256 percent
    ) external returns (uint256 amount0, uint256 amount1) {
        for (uint256 i = 0; i < self.tokenIds.length(); i++) {
            uint256 tokenId = self.tokenIds.at(i);
            (,,,,,,, uint128 totalLiquidity,,,,) = positionManager.positions(tokenId);
            uint256 liquidity = totalLiquidity * percent / Constants.PRECISION;

            (uint256 liq0, uint256 liq1) = positionManager.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: uint128(liquidity),
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: type(uint256).max
                })
            );
            uint256 fees0;
            uint256 fees1;
            {
                // everything besides just claimed liquidity are fees
                (,,,,,,,,,, uint256 owed0, uint256 owed1) = positionManager.positions(tokenId);
                fees0 = owed0 - liq0;
                fees1 = owed1 - liq1;
            }

            (uint256 collected0, uint256 collected1) = positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: uint128(fees0 * liquidity / totalLiquidity + liq0),
                    amount1Max: uint128(fees1 * liquidity / totalLiquidity + liq1)
                })
            );

            amount0 += collected0;
            amount1 += collected1;
        }
    }

    /**
     * @notice Claims all owed tokens from all positions.
     * @param positionManager The address of the Uniswap V3 position manager
     */
    function claimAll(Positions storage self, INonfungiblePositionManager positionManager) external {
        for (uint256 i = 0; i < self.tokenIds.length(); i++) {
            positionManager.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: self.tokenIds.at(i),
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }
    }

    /**
     * @notice Calculates the total owed amounts of tokens across all positions in the vault.
     * @param positionManager The address of the Uniswap V3 position manager
     * @return amount0 The total owed amount of token0
     * @return amount1 The total owed amount of token1
     */
    function getTotalOwed(Positions storage self, INonfungiblePositionManager positionManager)
        external
        view
        returns (uint128 amount0, uint128 amount1)
    {
        for (uint256 i = 0; i < self.tokenIds.length(); i++) {
            uint256 tokenId = self.tokenIds.at(i);
            (,,,,,,,,,, uint128 owed0, uint128 owed1) = positionManager.positions(tokenId);
            amount0 += owed0;
            amount1 += owed1;
        }
    }

    /**
     * @notice Calculates and returns the total amounts of tokens held across all positions in the vault.
     * @dev This includes the amounts derived from liquidity positions using the given pool price
     *      and adds any tokens owed from the positions.
     * @param positionManager The address of the Uniswap V3 position manager
     * @param sqrtPrice The current pool price
     * @return amount0 The total amount of token0
     * @return amount1 The total amount of token1
     */
    function getTotalAmountsAt(Positions storage self, INonfungiblePositionManager positionManager, uint160 sqrtPrice)
        external
        view
        returns (uint256 amount0, uint256 amount1)
    {
        for (uint256 i = 0; i < self.tokenIds.length(); i++) {
            uint256 tokenId = self.tokenIds.at(i);
            (,,,,,,,,,, uint128 owed0, uint128 owed1) = positionManager.positions(tokenId);
            amount0 += owed0;
            amount1 += owed1;

            PositionsLogic.Position memory position = self.positions[tokenId];
            (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
            (uint256 amount0_, uint256 amount1_) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPrice,
                TickMath.getSqrtRatioAtTick(position.tickLower),
                TickMath.getSqrtRatioAtTick(position.tickUpper),
                liquidity
            );
            amount0 += amount0_;
            amount1 += amount1_;
        }
    }

    /**
     * @notice Gets the length of the token IDs set
     * @return The length of the token IDs set
     */
    function getTokenIdsLength(Positions storage self) external view returns (uint256) {
        return self.tokenIds.length();
    }

    /**
     * @notice Gets the position at a given index
     * @param id The index of the position to get
     * @return The position at the given index
     */
    function getPositionAt(Positions storage self, uint256 id) external view returns (PositionsLogic.Position memory) {
        return self.positions[self.tokenIds.at(id)];
    }
}

library OraclesLogic {
    using OraclesLogic for OraclesLogic.Oracles;
    using OracleData for IChainlinkOracle;

    struct Oracles {
        /// @notice Mapping of tokens to their oracles
        mapping(address token => IChainlinkOracle oracle) oracles;
    }

    function getPrice(Oracles storage self, address asset_) public view returns (uint256) {
        return self.oracles[asset_].getPrice();
    }

    /**
     * @notice Converts an amount of the assetIn to the assetOut
     * @param assetIn The address of the asset to convert from
     * @param assetOut The address of the asset to convert to
     * @param amount The amount to convert
     * @return The equivalent amount in the assetOut
     */
    function convert(Oracles storage self, address assetIn, address assetOut, uint256 amount)
        external
        view
        returns (uint256)
    {
        if (assetIn != assetOut) {
            return (amount * getPrice(self, assetIn) / (10 ** IERC20Metadata(assetIn).decimals()))
                * (10 ** IERC20Metadata(assetOut).decimals()) / getPrice(self, assetOut);
        }
        return amount;
    }

    /**
     * @dev Calculates the square root of the price ratio between two tokens based on data from oracle.
     */
    function getSqrtPriceX96(Oracles storage self, IERC20Metadata token0, IERC20Metadata token1)
        external
        view
        returns (uint160)
    {
        uint256 price0 = getPrice(self, address(token0));
        uint256 price1 = getPrice(self, address(token1));

        return uint160(
            Math.sqrt(Math.mulDiv(price0, 2 ** 96, price1))
                * Math.sqrt(Math.mulDiv(10 ** token1.decimals(), 2 ** 96, 10 ** token0.decimals()))
        );
    }
}

library VaultLogic {
    using PositionsLogic for PositionsLogic.Positions;
    using OraclesLogic for OraclesLogic.Oracles;

    error Slippage();

    struct Immutables {
        INonfungiblePositionManager positionManager;
        IERC20Metadata token0;
        IERC20Metadata token1;
        uint8 token0Decimals;
        uint8 token1Decimals;
        IVault token0Vault;
        IVault token1Vault;
        address asset;
    }

    function openPositionIfNeed(
        uint256 assetsToSpend,
        uint24 fee,
        uint160 price1,
        uint160 price2,
        address tokenTreasure,
        IUniswapV3Pool pool,
        Immutables memory immutables,
        OraclesLogic.Oracles storage oracles,
        PositionsLogic.Positions storage positions
    ) external {
        (uint160 currentPrice,,,,,,) = pool.slot0();
        if (price1 > price2) (price1, price2) = (price2, price1);

        bool isToken0 = tokenTreasure == address(immutables.token0);
        assetsToSpend =
            oracles.convert(immutables.asset, address(isToken0 ? immutables.token1 : immutables.token0), assetsToSpend);

        // Move range if its outdated
        if ((isToken0 && currentPrice < price2)) {
            price1 -= (price2 - currentPrice);
            price2 = currentPrice;
        } else if (!isToken0 && currentPrice > price1) {
            price2 += (currentPrice - price1);
            price1 = currentPrice;
        }

        (int24 tickLower, int24 tickUpper) = _adjustTicks(isToken0, price1, price2, pool.tickSpacing());

        _openPosition(isToken0, assetsToSpend, fee, tickLower, tickUpper, immutables, positions);
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
    function _adjustTicks(bool isToken0, uint160 priceLower, uint160 priceUpper, int24 tickSpacing)
        private
        pure
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
     * @notice Creates a new Uniswap LP position using the specified amount of tokens and price range.
     * @dev This function is internal and is called by `openPositionIfNeed` to initialize an LP position
     *      once it's determined that additional LP positions are needed to acquire more treasure tokens.
     *
     * @param amount The amount of free tokens intended for exchange into the treasure token.
     * @param tickLower The lower tick for position
     * @param tickUpper The upper tick for position
     * @param fee_ The fee tier for the Uniswap V3 pool position.
     */
    function _openPosition(
        bool isToken0,
        uint256 amount,
        uint24 fee_,
        int24 tickLower,
        int24 tickUpper,
        Immutables memory immutables,
        PositionsLogic.Positions storage positions
    ) private {
        {
            IVault vault = isToken0 ? immutables.token1Vault : immutables.token0Vault;
            uint256 balance =
                isToken0 ? immutables.token1.balanceOf(address(this)) : immutables.token0.balanceOf(address(this));
            // if we have less than the amount we need to redeem assets from the farmings
            if (balance < amount) {
                amount = balance
                    + vault.redeem(
                        (amount - balance) * 10 ** vault.decimals() / vault.sharePrice(), address(this), address(this), 0
                    );
            }
        }
        uint256 tokenId;
        {
            (uint256 amount0Desired, uint256 amount1Desired) = isToken0 ? (uint256(0), amount) : (amount, 0);

            (tokenId,,,) = immutables.positionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: address(immutables.token0),
                    token1: address(immutables.token1),
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
        }

        positions.add(tokenId, PositionsLogic.Position({tickLower: tickLower, tickUpper: tickUpper, fee: fee_}));
    }

    /**
     * @notice Internal function to deposit assets
     */
    function deposit(
        uint256 assets,
        uint32 maxSlippage,
        uint256 currentPercentage,
        address tokenTreasure,
        address pool,
        Immutables memory immutables,
        OraclesLogic.Oracles storage oracles
    ) external {
        bool isToken0 = tokenTreasure == address(immutables.token0);
        // we try to keep the ratio of tokens in the vault
        if (tokenTreasure == immutables.asset) {
            swap(
                isToken0,
                assets * (Constants.PRECISION - currentPercentage) / Constants.PRECISION,
                maxSlippage,
                pool,
                immutables,
                oracles
            );
        } else {
            swap(!isToken0, assets * currentPercentage / Constants.PRECISION, maxSlippage, pool, immutables, oracles);
        }
    }

    /**
     * @notice Internal function to redeem shares
     */
    function redeem(
        uint256 shares,
        uint256 totalSupply,
        Immutables memory immutables,
        PositionsLogic.Positions storage positions
    ) external returns (uint256 amount0, uint256 amount1) {
        amount0 = immutables.token0.balanceOf(address(this)) * shares / totalSupply;
        amount1 = immutables.token1.balanceOf(address(this)) * shares / totalSupply;

        uint256 farmingShares0 = immutables.token0Vault.balanceOf(address(this)) * shares / totalSupply;
        uint256 farmingShares1 = immutables.token1Vault.balanceOf(address(this)) * shares / totalSupply;

        if (farmingShares0 > 0) {
            amount0 += immutables.token0Vault.redeem(farmingShares0, address(this), address(this), 0);
        }

        if (farmingShares1 > 0) {
            amount1 += immutables.token1Vault.redeem(farmingShares1, address(this), address(this), 0);
        }

        (uint256 positions0, uint256 positions1) = positions.removeLiquidityAndRewardsPercent(
            immutables.positionManager, shares * Constants.PRECISION / totalSupply
        );
        amount0 += positions0;
        amount1 += positions1;
    }

    /**
     * @dev Internal function that closes all positions
     */
    function closePositionsAll(Immutables memory immutables, PositionsLogic.Positions storage positions) public {
        for (uint256 i = positions.getTokenIdsLength(); i > 0; i--) {
            positions.closeAt(immutables.positionManager, i - 1);
        }
        positions.recalculateTicks();
    }

    /**
     * @dev Internal function that performs the closing of positions in a bad market
     */
    function closePositionsBadMarket(
        bool isToken0,
        int24 tickDiff,
        Immutables memory immutables,
        OraclesLogic.Oracles storage oracles,
        PositionsLogic.Positions storage positions
    ) external {
        int24 currentTick = TickMath.getTickAtSqrtRatio(oracles.getSqrtPriceX96(immutables.token0, immutables.token1));
        if ((isToken0 ? (currentTick - positions.highestTick) : (positions.lowestTick - currentTick)) > tickDiff) {
            closePositionsAll(immutables, positions);
        }
    }

    /**
     * @notice Deposits free funds into the vaults.
     */
    function investFreeMoney(Immutables memory immutables) external {
        immutables.token0Vault.deposit(immutables.token0.balanceOf(address(this)), address(this), 0);
        immutables.token1Vault.deposit(immutables.token1.balanceOf(address(this)), address(this), 0);
    }

    /**
     * @notice Internal function to perform a token swap on the DEX
     * @param zeroForOne Whether to swap token0 for token1 (true) or token1 for token0 (false)
     * @param amount The amount of tokens to swap
     * @return amountOut The amount of tokens received from the swap
     */
    function swap(
        bool zeroForOne,
        uint256 amount,
        uint32 maxSlippage,
        address pool,
        Immutables memory immutables,
        OraclesLogic.Oracles storage oracles
    ) public returns (uint256 amountOut) {
        // Execute the swap and capture the output amount
        if (amount == 0) return 0;
        (address from, address to) = zeroForOne
            ? (address(immutables.token0), address(immutables.token1))
            : (address(immutables.token1), address(immutables.token0));
        {
            (int256 amount0, int256 amount1) = IUniswapV3Pool(pool).swap(
                address(this),
                zeroForOne,
                int256(amount),
                zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                abi.encode(from, to)
            );

            // Return the output amount (convert from negative if needed)
            amountOut = uint256(-(zeroForOne ? amount1 : amount0));
        }
        // check slippage
        // we subtract 3 to avoid reverts caused by slippage with small values
        require(
            amountOut + 3
                >= oracles.convert(from, to, amount < 3 ? 0 : amount - 3) * (Constants.SLIPPAGE_PRECISION - maxSlippage)
                    / Constants.SLIPPAGE_PRECISION,
            Slippage()
        );
    }
}

/**
 * @title SeasonalVault
 * @notice Vault that manages assets based on crypto market seasons strategy
 * @dev Implements seasonal strategy for crypto asset management.
 * The vault logic is divided into several contracts to comply with bytecode size limits.
 */
contract SeasonalVault is BaseVault, IUniswapV3SwapCallback, IERC721Receiver {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.UintSet;
    using PositionsLogic for PositionsLogic.Positions;
    using OraclesLogic for OraclesLogic.Oracles;

    error InvalidTreasureToken(address token);

    /* ========== EVENTS ========== */

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

    PositionsLogic.Positions positions;

    /// @notice Maps fee tiers to pool addresses
    mapping(uint24 fee => address pool) public pools;

    /// @notice Mapping of tokens to their oracles
    OraclesLogic.Oracles oracles;

    /**
     * @notice The address of the token that is being accumulated
     * in the vault during the current period
     */
    IERC20Metadata public tokenTreasure;

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
        positions.lowestTick = TickMath.MIN_TICK;
        positions.highestTick = TickMath.MAX_TICK;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256 total) {
        (uint256 total0, uint256 total1) = getPositionAmounts();
        (uint256 amount0, uint256 amount1) = _getAmountsForFarmings();
        return _getInUnderlyingAsset(address(token0), total0 + _getBalance(address(token0)) + amount0)
            + _getInUnderlyingAsset(address(token1), total1 + _getBalance(address(token1)) + amount1);
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
        // We're using sqrt price from oracle to avoid pool price manipulations affect the result
        return positions.getTotalAmountsAt(positionManager, oracles.getSqrtPriceX96(token0, token1));
    }

    /**
     * @notice Optimistically calculates the percentage of the TVL represented by the treasure token.
     * @return The percentage of the fund held as the treasure token.
     */
    function getNettoPartForTokenOptimistic() public view returns (uint256) {
        (uint256 total0, uint256 total1) = getPositionAmounts();
        if (isToken0) {
            return (
                _getInUnderlyingAsset(
                    address(tokenTreasure),
                    total0 + _getBalance(address(tokenTreasure)) + token0Vault.getBalanceInUnderlying(address(this))
                ) + _getInUnderlyingAsset(address(token1), total1)
            ) * Constants.PRECISION / totalAssets();
        } else {
            return (
                _getInUnderlyingAsset(
                    address(tokenTreasure),
                    total1 + _getBalance(address(tokenTreasure)) + token1Vault.getBalanceInUnderlying(address(this))
                ) + _getInUnderlyingAsset(address(token0), total0)
            ) * Constants.PRECISION / totalAssets();
        }
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
    function getNettoTVL(address inAsset) external view returns (uint256) {
        return oracles.convert(asset(), inAsset, totalAssets());
    }

    /**
     * @notice Retrieves the current square root price and tick of a Uniswap pool.
     * @param pool The address of the Uniswap pool
     * @return sqrtPriceX96 The current square root price of the pool
     * @return tick The current tick of the pool
     */
    function getPoolState(address pool) public view returns (uint160 sqrtPriceX96, int24 tick) {
        (sqrtPriceX96, tick,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    /**
     * @notice Returns token IDs of all positions
     * @return Array of token IDs
     */
    function getTokenIds() external view returns (uint256[] memory) {
        return positions.tokenIds.values();
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
        require(token_ == address(token0) || token_ == address(token1), InvalidTreasureToken(token_));
        tokenTreasure = IERC20Metadata(token_);
        isToken0 = tokenTreasure == token0;
        positions.recalculateTicks();
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
            oracles.oracles[tokens_[i]] = IChainlinkOracle(oracles_[i]);
        }
    }

    /**
     * @notice Updates the pool for a particular fee tier.
     * @param fee The fee tier to update
     * @return pool The address of the updated pool
     */
    function updatePoolForFee(uint24 fee) external onlyRole(MANAGER_ROLE) returns (address pool) {
        pool = _getPool(fee);
        pools[fee] = pool;
    }

    /**
     * @notice Deposits free funds into the vaults.
     */
    function investFreeMoney() external onlyRole(MANAGER_ROLE) {
        VaultLogic.investFreeMoney(_getImmutables());
    }

    /**
     * @notice Claims earned fees from the liquidity positions.
     */
    function claimDEX() external onlyRole(MANAGER_ROLE) {
        positions.claimAll(positionManager);
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

        // amount of assets needed to open position calculated in the underlying asset of the vault
        uint256 assetsToSpend = totalAssets() * (percentageTreasureDesired - currentPercentage) / Constants.PRECISION;
        VaultLogic.openPositionIfNeed({
            assetsToSpend: assetsToSpend,
            fee: fee,
            price1: price1,
            price2: price2,
            tokenTreasure: address(tokenTreasure),
            pool: IUniswapV3Pool(_getOrUpdatePool(fee)),
            immutables: _getImmutables(),
            oracles: oracles,
            positions: positions
        });
    }

    /**
     * @notice Closes all Uniswap positions.
     * @dev This function closes all Uniswap positions, regardless of whether they are currently held in the treasure
     *      token or not.
     */
    function closePositionsAll() external onlyRole(MANAGER_ROLE) {
        VaultLogic.closePositionsAll(_getImmutables(), positions);
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
        for (uint256 i = positions.tokenIds.length(); i > 0; i--) {
            uint256 tokenId = positions.tokenIds.at(i - 1);
            PositionsLogic.Position memory position = positions.positions[tokenId];
            (, int24 currentTick) = getPoolState(pools[position.fee]);

            if ((isToken0 && position.tickLower > currentTick) || (!isToken0 && position.tickUpper < currentTick)) {
                positions.close(positionManager, tokenId);
                changed = true;
            }
        }
        if (changed) positions.recalculateTicks();
    }

    /**
     * @notice Closes all Uniswap positions when the current market price moves adversely beyond a threshold.
     * @dev If the current market price is worse than the worst boundary of each LP range by a percentage defined by `tickDiff`,
     *      this function will close all open Uniswap positions. This mechanism is intended to protect against adverse market
     *      movements where maintaining the position would not earn fees effectively.
     */
    function closePositionsBadMarket() external onlyRole(MANAGER_ROLE) {
        VaultLogic.closePositionsBadMarket(isToken0, tickDiff, _getImmutables(), oracles, positions);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function _deposit(uint256 assets) internal override returns (uint256 totalAssetsBefore) {
        totalAssetsBefore = _totalAssetsPrecise() - assets;
        VaultLogic.deposit(
            assets,
            maxSlippage,
            _getNettoPartForTokenReal(tokenTreasure, assets),
            address(tokenTreasure),
            _getOrUpdatePool(feeForSwaps),
            _getImmutables(),
            oracles
        );
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        VaultLogic.Immutables memory immutables = _getImmutables();
        (uint256 amount0, uint256 amount1) = VaultLogic.redeem(shares, totalSupply(), immutables, positions);

        assets = asset() == address(token0)
            ? amount0 + VaultLogic.swap(false, amount1, maxSlippage, _getOrUpdatePool(feeForSwaps), immutables, oracles)
            : amount1 + VaultLogic.swap(true, amount0, maxSlippage, _getOrUpdatePool(feeForSwaps), immutables, oracles);
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
            + _getBalance(address(inAsset)) - (asset() == address(tokenTreasure) ? depositedAmount : 0);
        // we need to subtract deposited amount from the total assets
        uint256 totalAssets_ = totalAssets() - depositedAmount;
        if (totalAssets_ == 0) return 0;
        return _getInUnderlyingAsset(address(inAsset), totalInRequested) * Constants.PRECISION / totalAssets_;
    }

    /**
     * @notice Retrieves and stores a pool for a particular fee tier.
     * @param fee Fee tier to retrieve
     * @return pool Address of the pool
     */
    function _getOrUpdatePool(uint24 fee) internal returns (address pool) {
        pool = pools[fee];
        if (pool == address(0)) {
            pool = _getPool(fee);
            pools[fee] = pool;
        }
    }

    /**
     * @notice Internal function to get the pool
     * @param fee The fee tier
     * @return The pool
     */
    function _getPool(uint24 fee) private view returns (address) {
        return IUniswapV3Factory(positionManager.factory()).getPool(address(token0), address(token1), fee);
    }

    /**
     * @notice Converts an amount to the vault's underlying asset value
     * @param asset_ The address of the asset to convert from
     * @param amount The amount to convert
     * @return The equivalent amount in the vault's underlying asset
     */
    function _getInUnderlyingAsset(address asset_, uint256 amount) internal view returns (uint256) {
        return oracles.convert(asset_, asset(), amount);
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
     * @notice Internal function to get the immutables
     * @return immutables The immutables
     */
    function _getImmutables() private view returns (VaultLogic.Immutables memory immutables) {
        return VaultLogic.Immutables({
            positionManager: positionManager,
            token0: token0,
            token1: token1,
            token0Decimals: token0Decimals,
            token1Decimals: token1Decimals,
            token0Vault: token0Vault,
            token1Vault: token1Vault,
            asset: asset()
        });
    }

    /**
     * @notice Internal function to get the token balance
     * @param token The address of the token to get the balance
     * @return The balance
     */
    function _getBalance(address token) private view returns (uint256) {
        return IERC20Metadata(token).balanceOf(address(this));
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
