// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {BaseVault, IERC20Metadata} from "../BaseVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {IHubPool} from "../interfaces/across/IHubPool.sol";
import {IAcceleratingDistributor} from "../interfaces/across/IAcceleratingDistributor.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OracleData} from "../libraries/OracleData.sol";

/**
 * @title AcrossVault
 * @notice A vault contract for managing Across Protocol liquidity
 */
contract AcrossVault is BaseVault {
    using SafeERC20 for IERC20Metadata;
    using OracleData for IChainlinkOracle;

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

    /// @notice The oracle for the WETH
    IChainlinkOracle public immutable wethOracle;

    /// @notice The oracle for the asset
    IChainlinkOracle public immutable assetOracle;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice The amount of rewards reinvested since last claim
    uint256 public reinvested;

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
     * @param _wethOracle The oracle for the WETH
     * @param _assetOracle The oracle for the asset
     */
    constructor(
        IERC20Metadata _asset,
        address _pool,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        address _staking,
        address _acxWethPool,
        address _assetWethPool,
        address _weth,
        IChainlinkOracle _wethOracle,
        IChainlinkOracle _assetOracle
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        pool = IHubPool(payable(_pool));
        (address lpToken_,,,,,) = IHubPool(payable(_pool)).pooledTokens(address(_asset));
        lpToken = IERC20Metadata(lpToken_);
        staking = IAcceleratingDistributor(_staking);
        acx = IERC20Metadata(staking.rewardToken());
        acxWethPool = IUniswapV3Pool(_acxWethPool);
        assetWethPool = IUniswapV3Pool(_assetWethPool);
        weth = IERC20Metadata(_weth);
        wethOracle = _wethOracle;
        assetOracle = _assetOracle;
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
     * @notice Claims and reinvests accumulated rewards
     * @dev Withdraws ACX rewards from staking
     * @return assets The amount of assets reinvested
     */
    function claimReinvest(address _recipient) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 assets) {
        assets = _reinvest();

        // Claim ACX rewards from staking contract
        staking.withdrawReward(address(lpToken));

        // Transfer acx rewards to recipient
        acx.safeTransfer(_recipient, acx.balanceOf(address(this)));

        reinvested = 0;
    }

    /**
     * @notice Reinvests equal amount of assets as the amount of rewards
     */
    function reinvest() external onlyRole(MANAGER_ROLE) returns (uint256 assets) {
        assets = _reinvest();
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
     * @notice Gets the sqrt price of ACX in WETH using the ACX/WETH Uniswap V3 pool
     * @return price The sqrt price of ACX in WETH
     */
    function getACXPrice() public view returns (uint256) {
        // twap
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0;
        secondsAgos[1] = 1800;

        (int56[] memory tickCumulatives,) = acxWethPool.observe(secondsAgos);
        int56 tickCumulativeDelta = tickCumulatives[0] - tickCumulatives[1];
        int56 timeElapsed = int56(uint56(secondsAgos[1]));

        int24 averageTick = int24(tickCumulativeDelta / timeElapsed);
        if (tickCumulativeDelta < 0 && (tickCumulativeDelta % timeElapsed != 0)) {
            averageTick--;
        }

        return uint256(TickMath.getSqrtRatioAtTick(averageTick));
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Reinvests equal amount of assets as the amount of rewards
     */
    function _reinvest() internal returns (uint256 assets) {
        uint256 rewards = staking.getOutstandingRewards(address(lpToken), address(this));
        if (rewards > reinvested) {
            assets = _calculateACXInAsset(rewards - reinvested);
            _deposit(assets);
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
        uint256 sqrtPrice = getACXPrice();
        acxInAsset = acx < weth
            ? Math.mulDiv(amount, sqrtPrice * sqrtPrice, 2 ** 192)
            : Math.mulDiv(amount, 2 ** 192, sqrtPrice * sqrtPrice);
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
        IChainlinkOracle oracle = token == address(weth) ? wethOracle : assetOracle;
        // returns price in the vault decimals
        return uint256(oracle.getPrice()) * (10 ** decimals()) / 10 ** (oracle.decimals());
    }

    /**
     * @notice Deposits assets into the Across pool and stakes the received LP tokens
     * @param assets The amount of assets to deposit
     */
    function _deposit(uint256 assets) internal override returns (uint256 totalAssetsBefore) {
        totalAssetsBefore = _totalAssetsPrecise();
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
}
