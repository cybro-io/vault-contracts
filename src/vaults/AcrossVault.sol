// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {BaseVault, IERC20Metadata} from "../BaseVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {IHubPool} from "../interfaces/across/IHubPool.sol";
import {IAcceleratingDistributor} from "../interfaces/across/IAcceleratingDistributor.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title AcrossVault
 * @notice A vault contract for managing Across Protocol liquidity
 */
contract AcrossVault is BaseVault, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20Metadata;

    /* ========== ERRORS ========== */

    /// @notice Error thrown when a swap doesn't meet the minimum required output
    error AcrossVault__slippage();

    /* ========== IMMUTABLE STATE VARIABLES ========== */

    /// @notice The Across Hub Pool contract that manages LP tokens
    IHubPool public immutable pool;

    /// @notice The LP token received when providing liquidity to the Across pool
    IERC20Metadata public immutable lpToken;

    /// @notice The staking contract used to stake LP tokens and earn rewards
    IAcceleratingDistributor public immutable staking;

    /// @notice The Across governance token
    IERC20Metadata public immutable acx;

    /// @notice The wrapped ETH token
    IERC20Metadata public immutable weth;

    /// @notice Uniswap V3 pool for ACX/WETH pair
    IUniswapV3Pool public immutable acxWethPool;

    /// @notice Uniswap V3 pool for asset/WETH pair
    IUniswapV3Pool public immutable assetWethPool;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice The amount of rewards reinvested since last claim
    uint256 public reinvested;

    /// @notice The oracles for the WETH and asset
    mapping(address token => IChainlinkOracle oracle) public oracles;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the AcrossVault contract
     * @param _asset The underlying asset of the vault
     * @param _pool The address of the Across HubPool
     * @param _feeProvider The fee provider contract
     * @param _feeRecipient The address that receives fees
     * @param _staking The address of the AcceleratingDistributor contract
     * @param _acxWethPool The address of the ACX/WETH Uniswap V3 pool
     * @param _assetWethPool The address of the asset/WETH Uniswap V3 pool (or address(0) if asset is WETH)
     * @param _weth The address of the WETH token
     */
    constructor(
        IERC20Metadata _asset,
        address _pool,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        address _staking,
        address _acxWethPool,
        address _assetWethPool,
        address _weth
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        pool = IHubPool(payable(_pool));
        (address lpToken_,,,,,) = IHubPool(payable(_pool)).pooledTokens(address(_asset));
        lpToken = IERC20Metadata(lpToken_);
        staking = IAcceleratingDistributor(_staking);
        acx = IERC20Metadata(staking.rewardToken());
        acxWethPool = IUniswapV3Pool(_acxWethPool);
        assetWethPool = IUniswapV3Pool(_assetWethPool);
        weth = IERC20Metadata(_weth);
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the AcrossVault contract
     * @dev Approves the pool and staking contracts to spend the vault's tokens
     * @param admin The address of the admin
     * @param name The name of the vault token
     * @param symbol The symbol of the vault token
     * @param manager The address of the manager
     */
    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        // Approve pool to spend asset and staking contract to spend LP tokens
        IERC20Metadata(asset()).forceApprove(address(pool), type(uint256).max);
        lpToken.forceApprove(address(staking), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Sets oracles for weth and asset
     * @param wethOracle The oracle for weth
     * @param assetOracle The oracle for asset
     */
    function setOracles(IChainlinkOracle wethOracle, IChainlinkOracle assetOracle) external onlyRole(MANAGER_ROLE) {
        oracles[address(weth)] = wethOracle;
        oracles[asset()] = assetOracle;
    }

    /**
     * @notice Claims and reinvests accumulated rewards
     * @dev Withdraws ACX rewards from staking, swaps to asset and deposits back into the pool
     * @param minAssets The minimum amount of assets expected after swap
     * @return assets The amount of assets obtained after swapping rewards
     */
    function claimReinvest(uint256 minAssets) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 assets) {
        _reinvest();

        // Claim ACX rewards from staking contract
        staking.withdrawReward(address(lpToken));
        // Swap ACX to the underlying asset
        assets = _swapToAssets(acx.balanceOf(address(this)));

        // Revert if slippage is too high
        if (assets < minAssets) revert AcrossVault__slippage();

        reinvested = 0;
    }

    /**
     * @notice Reinvests equal amount of assets as the amount of rewards
     */
    function reinvest() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _reinvest();
    }

    /**
     * @notice Quotes the amount of assets to reinvest
     * @return assets The amount of assets to reinvest
     */
    function quoteReinvest() external view returns (uint256) {
        uint256 rewards = staking.getOutstandingRewards(address(lpToken), address(this));
        return _calculateACXInAsset(rewards - reinvested);
    }

    /**
     * @notice Gets the amount of rewards in staking contract
     * @return rewards The amount of rewards
     */
    function getRewards() external view returns (uint256) {
        return staking.getOutstandingRewards(address(lpToken), address(this));
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        return _stakedBalance() * _exchangeRateStored() / 1e18;
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view virtual override returns (uint256) {
        (,,, int256 utilizedReserves, uint256 liquidReserves, uint256 undistibutedLpFees) = pool.pooledTokens(asset());
        return uint256(int256(liquidReserves) + utilizedReserves - int256(undistibutedLpFees));
    }

    /**
     * @notice Gets the price of ACX in WETH using the ACX/WETH Uniswap V3 pool
     * @return price The price of ACX in WETH
     */
    function getACXPrice() public view returns (uint256) {
        // twap
        uint32[] memory secondsAgos = new uint32[](4);
        secondsAgos[0] = 0;
        secondsAgos[1] = 450;
        secondsAgos[2] = 900;
        secondsAgos[3] = 1800;

        (int56[] memory tickCumulatives,) = acxWethPool.observe(secondsAgos);
        uint256 sumPrice;
        for (uint256 i = 1; i < secondsAgos.length; i++) {
            int56 tickCumulativeDelta = tickCumulatives[0] - tickCumulatives[i];
            int56 timeElapsed = int56(uint56(secondsAgos[i]));

            int24 averageTick = int24(tickCumulativeDelta / timeElapsed);
            if (tickCumulativeDelta < 0 && (tickCumulativeDelta % timeElapsed != 0)) {
                averageTick--;
            }

            uint256 sqrtPrice = uint256(TickMath.getSqrtRatioAtTick(averageTick));
            sumPrice += (sqrtPrice * sqrtPrice) >> 96;
        }
        return sumPrice / 3;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Reinvests equal amount of assets as the amount of rewards
     */
    function _reinvest() internal {
        uint256 rewards = staking.getOutstandingRewards(address(lpToken), address(this));
        if (rewards > reinvested) {
            _deposit(_calculateACXInAsset(rewards - reinvested));
            reinvested = rewards;
        }
    }

    /**
     * @notice Returns the amount of LP tokens staked by this vault
     * @return The staked LP token balance
     */
    function _stakedBalance() internal view returns (uint256) {
        IAcceleratingDistributor.UserDeposit memory userStake = staking.getUserStake(address(lpToken), address(this));
        return userStake.cumulativeBalance;
    }

    /**
     * @notice Returns the current exchange rate between LP tokens and underlying assets
     * @dev The exchange rate is calculated from the pool's reserves
     * @return The exchange rate scaled by 1e18
     */
    function _exchangeRateStored() internal view returns (uint256) {
        (,,, int256 utilizedReserves, uint256 liquidReserves, uint256 undistibutedLpFees) = pool.pooledTokens(asset());
        return uint256(int256(liquidReserves) + utilizedReserves - int256(undistibutedLpFees)) * 1e18
            / lpToken.totalSupply();
    }

    /**
     * @notice Gets the precise total assets value using current exchange rate
     * @dev Calls exchangeRateCurrent which may update the rate on-chain
     * @return The precise total assets
     */
    function _totalAssetsPrecise() internal override returns (uint256) {
        return _stakedBalance() * pool.exchangeRateCurrent(asset()) / 1e18;
    }

    /**
     * @notice Calculates the amount of asset for a given amount of ACX
     * @param amount The amount of ACX
     * @return acxInAsset The amount of asset
     */
    function _calculateACXInAsset(uint256 amount) internal view returns (uint256 acxInAsset) {
        uint256 price = getACXPrice();
        acxInAsset = acx < weth ? Math.mulDiv(amount, price, 2 ** 96) : Math.mulDiv(amount, 2 ** 96, price);
        if (asset() != address(weth)) {
            acxInAsset = (acxInAsset * _getPrice(address(weth)) / (10 ** IERC20Metadata(address(weth)).decimals()))
                * (10 ** decimals()) / _getPrice(asset());
        }
    }

    /**
     * @notice Gets the latest price for a token using oracle
     * @param token The address of the token
     * @return The latest price from the oracle
     */
    function _getPrice(address token) internal view returns (uint256) {
        IChainlinkOracle oracle = oracles[token];
        (uint80 roundID, int256 price,, uint256 timestamp, uint80 answeredInRound) = oracle.latestRoundData();

        require(answeredInRound >= roundID, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink price reporting 0");

        // returns price in the vault decimals
        return uint256(price) * (10 ** decimals()) / 10 ** (oracle.decimals());
    }

    /**
     * @notice Deposits assets into the Across pool and stakes the received LP tokens
     * @param assets The amount of assets to deposit
     */
    function _deposit(uint256 assets) internal override {
        // Add liquidity to the Across pool and receive LP tokens
        pool.addLiquidity(asset(), assets);
        // Stake the LP tokens in the AcceleratingDistributor
        staking.stake(address(lpToken), lpToken.balanceOf(address(this)));
    }

    /**
     * @notice Redeems shares by unstaking LP tokens and removing liquidity from the pool
     * @param shares The amount of shares to redeem
     * @return assets The amount of assets redeemed
     */
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        uint256 assetsBefore = IERC20Metadata(asset()).balanceOf(address(this));
        // Calculate proportion of LP tokens to unstake based on shares
        staking.unstake(address(lpToken), shares * _stakedBalance() / totalSupply());
        // Remove liquidity from the Across pool
        pool.removeLiquidity(asset(), lpToken.balanceOf(address(this)), false);
        assets = IERC20Metadata(asset()).balanceOf(address(this)) - assetsBefore;
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address) internal pure override returns (bool) {
        return true;
    }

    /**
     * @notice Swaps ACX tokens to the vault's asset using Uniswap V3
     * @dev First swaps ACX to WETH, then WETH to asset if needed
     * @param amount The amount of ACX to swap
     * @return assets The amount of assets received after the swap
     */
    function _swapToAssets(uint256 amount) internal returns (uint256 assets) {
        // First swap: ACX to WETH
        bool zeroForOne = address(acx) < address(weth);
        (int256 amount0, int256 amount1) = acxWethPool.swap(
            address(this),
            zeroForOne,
            int256(amount),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            zeroForOne ? abi.encode(acx, asset()) : abi.encode(asset(), acx)
        );
        assets = uint256(-(zeroForOne ? amount1 : amount0));

        // Second swap: WETH to asset (if asset is not WETH)
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

    /* ========== UNISWAP CALLBACK ========== */

    /**
     * @notice Uniswap V3 swap callback for providing required token amounts during swaps
     * @dev Called by Uniswap pools during swap execution to request payment
     * @param amount0Delta Amount of the first token delta
     * @param amount1Delta Amount of the second token delta
     * @param data Encoded data containing swap details
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(amount0Delta > 0 || amount1Delta > 0);
        require(
            msg.sender == address(acxWethPool) || msg.sender == address(assetWethPool),
            "AcrossVault: invalid swap callback caller"
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
