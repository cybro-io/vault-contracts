// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {IVault} from "./interfaces/IVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {BaseVault} from "./BaseVault.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";

/**
 * @title OneClickIndex
 * @notice A contract for managing ERC20 token lending to multiple lending pools.
 */
contract OneClickIndex is BaseVault, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;

    error InvalidPoolAddress();
    error ArraysLengthMismatch();
    error Slippage();
    error InvalidSwapCallbackCaller();
    error NoAvailablePools();
    error DeviationNotPositive();
    error DeviationNotNegative();
    error InvalidFromPoolAddress();
    error InvalidToPoolAddress();
    error RebalanceFailedForFromPool();
    error RebalanceFailedForToPool();
    error StalePrice();
    error RoundNotComplete();
    error ChainlinkPriceReportingZero();

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when a new lending pool is added
     * @param poolAddress The address of the lending pool
     */
    event LendingPoolAdded(address indexed poolAddress);

    /**
     * @notice Emitted when a lending pool is removed
     * @param poolAddress The address of the removed lending pool
     */
    event LendingPoolRemoved(address indexed poolAddress);

    /**
     * @notice Emitted when a lending pool's share is updated
     * @param poolAddress The address of the updated lending pool
     * @param newLendingShare The new share allocated to the lending pool
     */
    event LendingPoolUpdated(address indexed poolAddress, uint256 newLendingShare);

    /* ========== CONSTANTS ========== */

    /// @notice Role identifier for strategists
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    /// @notice Maximum number of lending pools for auto rebalance
    uint256 public constant maxPools = 1000;

    /// @notice Precision for slippage
    uint32 public constant slippagePrecision = 10000;

    /* ========== STATE VARIABLES ========== */

    /// @notice Mapping of lending pool addresses to their respective lending shares (in scaled units)
    mapping(address => uint256) public lendingShares;

    /// @notice Set of lending pool addresses
    EnumerableSet.AddressSet private lendingPoolAddresses;

    /// @notice Total lending shares across all pools
    uint256 public totalLendingShares;

    /// @notice Mapping of token pairs to Uniswap V3 pools for swapping
    mapping(address from => mapping(address to => IUniswapV3Pool pool)) public swapPools;

    /// @notice Mapping of tokens to their oracles
    mapping(address token => IChainlinkOracle oracle) public oracles;

    /// @notice Maximum slippage tolerance
    uint32 public maxSlippage;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor for OneClickIndex contract
     * @param _asset The ERC20 asset managed by the vault
     * @param _feeProvider The fee provider contract
     * @param _feeRecipient The address that receives the fees
     */
    constructor(IERC20Metadata _asset, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVault(_asset, _feeProvider, _feeRecipient)
    {
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the contract with admin
     * @param admin The address of the admin
     * @param name The name of the ERC20 token representing vault shares
     * @param symbol The symbol of the ERC20 token representing vault shares
     * @param strategist The address of the strategist
     * @param manager The address of the manager
     */
    function initialize(address admin, string memory name, string memory symbol, address strategist, address manager)
        public
        initializer
    {
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
        _grantRole(STRATEGIST_ROLE, strategist);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Adds multiple lending pools
     * @param poolAddresses Array of lending pool addresses
     */
    function addLendingPools(address[] memory poolAddresses) public onlyRole(STRATEGIST_ROLE) {
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            if (lendingPoolAddresses.add(poolAddresses[i])) {
                // Approve the lending pool to use the asset
                IERC20Metadata(IVault(poolAddresses[i]).asset()).forceApprove(poolAddresses[i], type(uint256).max);

                emit LendingPoolAdded(poolAddresses[i]);
            }
        }
    }

    /**
     * @notice Removes multiple lending pools
     * @param poolAddresses Array of lending pool addresses to remove
     *
     * Reduces the total lending shares and revokes asset approval for each pool.
     */
    function removeLendingPools(address[] memory poolAddresses) external onlyRole(STRATEGIST_ROLE) {
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            totalLendingShares -= lendingShares[poolAddresses[i]];

            delete lendingShares[poolAddresses[i]];

            require(lendingPoolAddresses.remove(poolAddresses[i]));

            // Revoke approval for the lending pool
            IERC20Metadata(IVault(poolAddresses[i]).asset()).forceApprove(poolAddresses[i], 0);

            emit LendingPoolRemoved(poolAddresses[i]);
        }
    }

    /**
     * @notice Updates lending shares for multiple pools
     * @param poolAddresses Array of lending pool addresses
     * @param newLendingShares Array of new lending shares
     *
     * Adjusts the total lending shares to reflect the updated shares for each pool.
     */
    function setLendingShares(address[] memory poolAddresses, uint256[] memory newLendingShares)
        public
        onlyRole(MANAGER_ROLE)
    {
        if (poolAddresses.length != newLendingShares.length) revert ArraysLengthMismatch();
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            if (!lendingPoolAddresses.contains(poolAddresses[i])) revert InvalidPoolAddress();
            totalLendingShares = totalLendingShares - lendingShares[poolAddresses[i]] + newLendingShares[i];
            lendingShares[poolAddresses[i]] = newLendingShares[i];

            emit LendingPoolUpdated(poolAddresses[i], newLendingShares[i]);
        }
    }

    /**
     * @notice Sets the current slippage tolerance
     * @param _maxSlippage Slippage value
     */
    function setMaxSlippage(uint32 _maxSlippage) external onlyRole(MANAGER_ROLE) {
        maxSlippage = _maxSlippage;
    }

    /**
     * @notice Sets swap pools for token pairs
     * @param from Array of source tokens
     * @param to Array of target tokens
     * @param _swapPools Array of Uniswap V3 pools for swapping
     */
    function setSwapPools(address[] calldata from, address[] calldata to, IUniswapV3Pool[] calldata _swapPools)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < _swapPools.length; i++) {
            if (from[i] < to[i]) {
                swapPools[from[i]][to[i]] = _swapPools[i];
            } else {
                swapPools[to[i]][from[i]] = _swapPools[i];
            }
        }
    }

    /**
     * @notice Removes swap pools for token pairs
     * @param from Array of source tokens
     * @param to Array of target tokens
     */
    function removeSwapPools(address[] memory from, address[] memory to) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < from.length; i++) {
            if (from[i] < to[i]) {
                swapPools[from[i]][to[i]] = IUniswapV3Pool(address(0));
            } else {
                swapPools[to[i]][from[i]] = IUniswapV3Pool(address(0));
            }
        }
    }

    /**
     * @notice Sets oracles for tokens
     * @param tokens Array of tokens
     * @param oracles_ Array of corresponding oracles
     */
    function setOracles(address[] calldata tokens, IChainlinkOracle[] calldata oracles_)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            oracles[tokens[i]] = oracles_[i];
        }
    }

    /**
     * @notice Rebalances assets between two lending pools
     * @param from The address of the lending pool to withdraw from
     * @param to The address of the lending pool to deposit to
     * @param sharesToWithdraw The amount of shares to withdraw from the `from` pool
     */
    function rebalance(address from, address to, uint256 sharesToWithdraw) external onlyRole(MANAGER_ROLE) {
        if (!lendingPoolAddresses.contains(from)) revert InvalidFromPoolAddress();
        if (!lendingPoolAddresses.contains(to)) revert InvalidToPoolAddress();

        int256 deviationFrom = _computeDeviation(from);
        int256 deviationTo = _computeDeviation(to);

        if (deviationFrom <= 0) revert DeviationNotPositive();
        if (deviationTo > 0) revert DeviationNotNegative();

        IVault(to).deposit(
            _swap(
                IVault(from).asset(),
                IVault(to).asset(),
                IVault(from).redeem(sharesToWithdraw, address(this), address(this), 0)
            ),
            address(this),
            0
        );

        deviationFrom = _computeDeviation(from);
        deviationTo = _computeDeviation(to);

        if (deviationFrom < 0) revert RebalanceFailedForFromPool();
        if (deviationTo > 0) revert RebalanceFailedForToPool();
    }

    /**
     * @notice Automatically rebalances assets across all lending pools
     */
    function rebalanceAuto() external onlyRole(MANAGER_ROLE) {
        uint256 totalAssetsToRedistribute;
        uint256 totalAssetsToDeposit;
        address[maxPools] memory poolsToDeposit;
        uint256[maxPools] memory amountsToDeposit;
        uint256 count;

        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address pool = lendingPoolAddresses.at(i);
            uint256 poolBalance = _getBalance(pool);
            int256 deviation = int256(poolBalance) - int256(totalAssets() * lendingShares[pool] / totalLendingShares);

            if (deviation > 0) {
                uint256 redeemedAmount = IVault(pool).redeem(
                    uint256(deviation) * IVault(pool).balanceOf(address(this)) / poolBalance,
                    address(this),
                    address(this),
                    0
                );
                if (redeemedAmount > 0) {
                    totalAssetsToRedistribute += _swap(IVault(pool).asset(), asset(), redeemedAmount);
                }
            } else if (deviation < 0) {
                poolsToDeposit[count] = pool;
                amountsToDeposit[count] = uint256(-deviation);
                totalAssetsToDeposit += uint256(-deviation);
                count++;
            }
        }

        uint256 leftAssets = totalAssetsToRedistribute;
        for (uint256 i = 0; i < count; i++) {
            // Calculate how much to deposit based on available assets and total deviation
            uint256 depositAmount = (amountsToDeposit[i] * totalAssetsToRedistribute) / totalAssetsToDeposit;

            // Deposit the calculated amount into the pool
            if (depositAmount > 0) {
                leftAssets -= depositAmount;
                IVault(poolsToDeposit[i]).deposit(
                    _swap(asset(), IVault(poolsToDeposit[i]).asset(), depositAmount), address(this), 0
                );
            }
        }
        if (leftAssets > 0) {
            IVault(poolsToDeposit[count - 1]).deposit(
                _swap(asset(), IVault(poolsToDeposit[count - 1]).asset(), leftAssets), address(this), 0
            );
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the share price of a lending pool
     * @param pool The address of the lending pool
     * @return The share price of the pool
     */
    function getSharePriceOfPool(address pool) external view returns (uint256) {
        return IVault(pool).sharePrice();
    }

    /**
     * @notice Returns the balance of a lending pool in the underlying asset of this vault
     * @param pool The address of the lending pool
     * @return The balance of the pool
     */
    function getBalanceOfPool(address pool) external view returns (uint256) {
        return _getBalance(pool);
    }

    /**
     * @notice Returns array of all lending pools
     * @return Array of lending pools
     */
    function getPools() external view returns (address[] memory) {
        return lendingPoolAddresses.values();
    }

    /**
     * @notice Returns the count of lending pools
     * @return The number of lending pools
     */
    function getLendingPoolCount() external view returns (uint256) {
        return lendingPoolAddresses.length();
    }

    /**
     * @notice Returns the total assets managed by the vault
     * as the sum of the assets of all lending pools
     * @return The total assets
     */
    function totalAssets() public view override returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address poolAddress = lendingPoolAddresses.at(i);
            totalBalance += _getBalance(poolAddress);
        }
        return totalBalance;
    }

    /**
     * @notice Returns the weighted average of underlying TVL across all lending pools in the fund
     * @dev This function calculates the underlying TVL for complex fund structures.
     * The TVL of each pool is weighted by its relative share in the total fund.
     *
     * For example, if the fund has:
     * - 30% in Aave (TVL: 1000)
     * - 70% in Compound (TVL: 2000)
     * The weighted underlying TVL would be: (1000 * 0.3) + (2000 * 0.7) = 1700
     *
     * @return tvl The weighted average underlying TVL across all lending pools
     */
    function underlyingTVL() external view override returns (uint256) {
        uint256 tvl;
        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address poolAddress = lendingPoolAddresses.at(i);
            tvl += _getInUnderlyingAsset(
                IVault(poolAddress).asset(),
                IVault(poolAddress).underlyingTVL() * lendingShares[poolAddress] / totalLendingShares
            );
        }
        return tvl;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Computes the deviation of a pool's balance from its target allocation
     * @param pool The address of the lending pool
     * @return deviation The deviation of the pool's balance
     */
    function _computeDeviation(address pool) internal view returns (int256 deviation) {
        uint256 amount = (totalAssets() * lendingShares[pool]) / totalLendingShares;
        deviation = int256(_getBalance(pool)) - int256(amount);
    }

    /**
     * @notice Returns the balance of a lending pool
     * @param poolAddress The address of the lending pool
     * @return balance The balance of the pool
     */
    function _getBalance(address poolAddress) internal view returns (uint256) {
        return _getInUnderlyingAsset(
            IVault(poolAddress).asset(),
            IVault(poolAddress).balanceOf(address(this)) * IVault(poolAddress).sharePrice()
                / (10 ** IVault(poolAddress).decimals())
        );
    }

    /**
     * @notice Deposits assets into the lending pools proportionally to their shares
     * @param assets The amount of assets to deposit
     */
    function _deposit(uint256 assets) internal override {
        uint256 leftAssets = assets;
        uint256 leftShares = totalLendingShares;
        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address poolAddress = lendingPoolAddresses.at(i);
            leftShares -= lendingShares[poolAddress];

            uint256 amountToDeposit;
            if (leftShares == 0) {
                amountToDeposit = leftAssets;
            } else {
                amountToDeposit = assets * lendingShares[poolAddress] / totalLendingShares;
            }
            leftAssets -= amountToDeposit;

            if (amountToDeposit > 0) {
                IVault(poolAddress).deposit(
                    _swap(asset(), IVault(poolAddress).asset(), amountToDeposit), address(this), 0
                );
            }
            if (leftAssets == 0) {
                break;
            }
        }
    }

    /**
     * @notice Redeems shares from the lending pools proportionally
     * @param shares The amount of shares to redeem
     * @return assets The amount of assets redeemed
     */
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        if (lendingPoolAddresses.length() == 0) revert NoAvailablePools();

        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address poolAddress = lendingPoolAddresses.at(i);
            uint256 poolShareToRedeem = (shares * IVault(poolAddress).balanceOf(address(this))) / totalSupply();
            if (poolShareToRedeem > 0) {
                assets += _swap(
                    IVault(poolAddress).asset(),
                    asset(),
                    IVault(poolAddress).redeem(poolShareToRedeem, address(this), address(this), 0)
                );
            }
        }
    }

    /**
     * @notice Swaps tokens using the configured Uniswap V3 pools
     * @param from The address of the token to swap from
     * @param to The address of the token to swap to
     * @param amountIn The amount of tokens to swap
     * @return amountOut The amount of tokens received from the swap
     *
     * Validates slippage to ensure the swap is within acceptable thresholds.
     */
    function _swap(address from, address to, uint256 amountIn) internal returns (uint256 amountOut) {
        // If the tokens are the same, return the input amount
        if (from == to) return amountIn;
        bool zeroForOne = from < to;
        IUniswapV3Pool pool = zeroForOne ? swapPools[from][to] : swapPools[to][from];
        (int256 amount0, int256 amount1) = pool.swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            zeroForOne ? abi.encode(from, to) : abi.encode(to, from)
        );
        amountOut = uint256(-(zeroForOne ? amount1 : amount0));
        _checkSlippage(from, to, amountIn, amountOut);
    }

    /**
     * @notice Checks if the swap was within the allowed slippage
     * @param from The address of the token swapped from
     * @param to The address of the token swapped to
     * @param amountIn The initial amount of tokens swapped
     * @param amountOut The amount of tokens received
     *
     * Ensures that the price impact of the swap doesn't exceed the permitted slippage.
     */
    function _checkSlippage(address from, address to, uint256 amountIn, uint256 amountOut) internal view {
        uint256 amountInUsd = amountIn * _getPrice(from) / (10 ** IERC20Metadata(from).decimals());
        uint256 amountOutUsd = amountOut * _getPrice(to) / (10 ** IERC20Metadata(to).decimals());
        if (amountOutUsd < amountInUsd * (slippagePrecision - maxSlippage) / slippagePrecision) {
            revert Slippage();
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

        if (answeredInRound < roundID) revert StalePrice();
        if (timestamp == 0) revert RoundNotComplete();
        if (price <= 0) revert ChainlinkPriceReportingZero();

        // returns price in the vault decimals
        return uint256(price) * (10 ** decimals()) / 10 ** (oracle.decimals());
    }

    /**
     * @notice Converts an amount to the vault's underlying asset value
     * @param asset_ The address of the asset to convert from
     * @param amount The amount to convert
     * @return The equivalent amount in the vault's underlying asset
     */
    function _getInUnderlyingAsset(address asset_, uint256 amount) internal view returns (uint256) {
        if (asset_ != asset()) {
            return (amount * _getPrice(asset_) / (10 ** IERC20Metadata(asset_).decimals())) * (10 ** decimals())
                / _getPrice(asset());
        }
        return amount;
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return !lendingPoolAddresses.contains(token);
    }

    /**
     * @notice Uniswap V3 swap callback for providing required token amounts during swaps
     * @param amount0Delta Amount of the first token delta
     * @param amount1Delta Amount of the second token delta
     * @param data Encoded data containing swap details
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(amount0Delta > 0 || amount1Delta > 0);
        (address tokenIn, address tokenOut) = abi.decode(data, (address, address));

        if (address(swapPools[tokenIn][tokenOut]) != msg.sender) revert InvalidSwapCallbackCaller();

        // Transfer the required amount back to the pool
        if (amount0Delta > 0) {
            IERC20Metadata(tokenIn).safeTransfer(msg.sender, uint256(amount0Delta));
        } else {
            IERC20Metadata(tokenOut).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
