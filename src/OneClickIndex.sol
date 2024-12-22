// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {IVault} from "./interfaces/IVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {BaseVault} from "./BaseVault.sol";

/**
 * @title OneClickIndex
 * @notice A contract for managing ERC20 token lending to multiple lending pools.
 */
contract OneClickIndex is BaseVault {
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

    /* ========== STATE VARIABLES ========== */

    /// @notice Mapping of lending pool addresses to their respective lending shares (in scaled units)
    mapping(address => uint256) public lendingShares;

    /// @notice Set of lending pool addresses
    EnumerableSet.AddressSet private lendingPoolAddresses;

    /// @notice Total lending shares across all pools
    uint256 public totalLendingShares;

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
                IERC20Metadata(asset()).forceApprove(poolAddresses[i], type(uint256).max);

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
            IERC20Metadata(asset()).forceApprove(poolAddresses[i], 0);

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

        uint256 assets = IVault(from).redeem(sharesToWithdraw, address(this), address(this), 0);

        IVault(to).deposit(assets, address(this), 0);

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
                uint256 assets = IVault(pool).redeem(
                    uint256(deviation) * IVault(pool).balanceOf(address(this)) / poolBalance,
                    address(this),
                    address(this),
                    0
                );
                totalAssetsToRedistribute += assets;
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
                IVault(poolsToDeposit[i]).deposit(depositAmount, address(this), 0);
            }
        }
        if (leftAssets > 0) IVault(poolsToDeposit[count - 1]).deposit(leftAssets, address(this), 0);
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
     * @notice Returns the balance of a lending pool
     * @param pool The address of the lending pool
     * @return The balance of the pool
     */
    function getBalanceOfPool(address pool) external view returns (uint256) {
        return IVault(pool).balanceOf(address(this)) * IVault(pool).sharePrice() / 10 ** decimals();
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
            tvl += IVault(poolAddress).underlyingTVL() * lendingShares[poolAddress] / totalLendingShares;
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
     * @return The balance of the pool
     */
    function _getBalance(address poolAddress) internal view returns (uint256) {
        return IVault(poolAddress).balanceOf(address(this)) * IVault(poolAddress).sharePrice() / 10 ** decimals();
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
                IVault(poolAddress).deposit(amountToDeposit, address(this), 0);
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
                assets += IVault(poolAddress).redeem(poolShareToRedeem, address(this), address(this), 0);
            }
        }
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return !lendingPoolAddresses.contains(token);
    }
}
