// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

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

    uint32 public constant slippagePrecision = 10000;

    /* ========== STATE VARIABLES ========== */

    /// @notice Mapping of lending pool addresses to their respective lending shares (in scaled units)
    mapping(address => uint256) public lendingShares;

    /// @notice Set of lending pool addresses
    EnumerableSet.AddressSet private lendingPoolAddresses;

    /// @notice Total lending shares across all pools
    uint256 public totalLendingShares;

    mapping(address from => mapping(address to => IUniswapV3Pool pool)) public swapPools;
    mapping(address token => IChainlinkOracle oracle) public oracles;

    uint32 public slippage;

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
     */
    function setLendingShares(address[] memory poolAddresses, uint256[] memory newLendingShares)
        public
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            totalLendingShares = totalLendingShares - lendingShares[poolAddresses[i]] + newLendingShares[i];
            lendingShares[poolAddresses[i]] = newLendingShares[i];

            emit LendingPoolUpdated(poolAddresses[i], newLendingShares[i]);
        }
    }

    function setSlippage(uint32 _slippage) external onlyRole(MANAGER_ROLE) {
        slippage = _slippage;
    }

    function setSwapPools(address[] memory from, address[] memory to, IUniswapV3Pool[] memory _swapPools)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < _swapPools.length; i++) {
            swapPools[from[i]][to[i]] = _swapPools[i];
            IERC20Metadata(from[i]).forceApprove(address(_swapPools[i]), type(uint256).max);
        }
    }

    function removeSwapPools(address[] memory from, address[] memory to) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < from.length; i++) {
            IERC20Metadata(from[i]).forceApprove(address(swapPools[from[i]][to[i]]), 0);
            swapPools[from[i]][to[i]] = IUniswapV3Pool(address(0));
        }
    }

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
        require(lendingPoolAddresses.contains(from), "OneClickIndex: Invalid 'from' pool address");
        require(lendingPoolAddresses.contains(to), "OneClickIndex: Invalid 'to' pool address");

        int256 deviationFrom = _computeDeviation(from);
        int256 deviationTo = _computeDeviation(to);

        require(deviationFrom > 0, "OneClickIndex: Pool 'from' not deviated positively");
        require(deviationTo <= 0, "OneClickIndex: Pool 'to' not deviated negatively");

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

        require(deviationFrom >= 0, "OneClickIndex: Rebalance failed for 'from' pool");
        require(deviationTo <= 0, "OneClickIndex: Rebalance failed for 'to' pool");
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
                totalAssetsToRedistribute += _swap(
                    IVault(pool).asset(),
                    asset(),
                    IVault(pool).redeem(
                        uint256(deviation) * IVault(pool).balanceOf(address(this)) / poolBalance,
                        address(this),
                        address(this),
                        0
                    )
                );
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
        require(lendingPoolAddresses.length() > 0, "OneClickIndex: No lending pools available");

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

    function _swap(address from, address to, uint256 amountIn) internal returns (uint256 amountOut) {
        if (from == to) return amountIn;
        IUniswapV3Pool pool = swapPools[from][to];
        bool zeroForOne = from < to;
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

    function _checkSlippage(address from, address to, uint256 amountIn, uint256 amountOut) internal view {
        uint256 priceFrom = _getPrice(from);
        uint256 priceTo = _getPrice(to);
        uint256 amountInUsd = amountIn * priceFrom / (10 ** IERC20Metadata(from).decimals());
        uint256 amountOutUsd = (amountOut * priceTo / (10 ** IERC20Metadata(to).decimals()));
        require(
            slippagePrecision - amountOutUsd * slippagePrecision / amountInUsd < slippage, "OneClickIndex: Slippage"
        );
    }

    function _getPrice(address token) internal view returns (uint256) {
        IChainlinkOracle oracle = oracles[token];
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

        require(
            address(swapPools[tokenIn][tokenOut]) == msg.sender || address(swapPools[tokenOut][tokenIn]) == msg.sender,
            "OneClickIndex: invalid swap callback caller"
        );

        // Transfer the required amount back to the pool
        IERC20Metadata(tokenIn).safeTransfer(
            msg.sender, amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta)
        );
    }
}
