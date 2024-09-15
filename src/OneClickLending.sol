// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {BaseVault, IERC20Metadata} from "./BaseVault.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title OneClickLending
/// @notice A contract for managing ERC20 token lending to multiple lending pools.
contract OneClickLending is BaseVault {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ========== STATE VARIABLES ========== */

    /// @notice Mapping of lending pool addresses to their respective lending shares (in scaled units).
    mapping(address => uint256) public lendingShares;

    /// @notice Set of lending pool addresses.
    EnumerableSet.AddressSet private lendingPoolAddresses;

    /// @notice Total lending shares across all pools.
    uint256 public totalLendingShares;

    /* ========== EVENTS ========== */

    /// @notice Emitted when a new lending pool is added.
    /// @param poolAddress The address of the lending pool.
    event LendingPoolAdded(address indexed poolAddress);

    /// @notice Emitted when a lending pool is removed.
    /// @param poolAddress The address of the removed lending pool.
    event LendingPoolRemoved(address indexed poolAddress);

    /// @notice Emitted when a lending pool's share is updated.
    /// @param poolAddress The address of the updated lending pool.
    /// @param newLendingShare The new share allocated to the lending pool.
    event LendingPoolUpdated(address indexed poolAddress, uint256 newLendingShare);

    /* ========== CONSTRUCTOR AND INITIALIZER ========== */

    /**
     * @notice Constructor for OneClickLending contract.
     * @param _asset The ERC20 asset managed by the vault.
     */
    constructor(IERC20Metadata _asset) BaseVault(_asset) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with admin, name and symbol.
     * @param admin The address of the admin.
     * @param name The name of the ERC20 token.
     * @param symbol The symbol of the ERC20 token.
     */
    function initialize(address admin, string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __BaseVault_init(admin);
    }

    /* ========== LENDING POOL MANAGEMENT METHODS ========== */

    /**
     * @notice Adds multiple lending pools.
     * @param poolAddresses Array of lending pool addresses.
     */
    function addLendingPools(address[] memory poolAddresses) external onlyOwner {
        address poolAddress;
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            poolAddress = poolAddresses[i];
            lendingPoolAddresses.add(poolAddress);

            // Approve the lending pool to use the asset.
            IERC20Metadata(asset()).forceApprove(address(poolAddress), type(uint256).max);

            emit LendingPoolAdded(poolAddress);
        }
    }

    /**
     * @notice Removes multiple lending pools.
     * @param poolAddresses Array of lending pool addresses to remove.
     */
    function removeLendingPools(address[] memory poolAddresses) external onlyOwner {
        address poolAddress;
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            poolAddress = poolAddresses[i];
            totalLendingShares -= lendingShares[poolAddress];

            delete lendingShares[poolAddress];

            require(lendingPoolAddresses.remove(poolAddress));

            // Revoke approval for the lending pool.
            IERC20Metadata(asset()).forceApprove(address(poolAddress), 0);

            emit LendingPoolRemoved(poolAddress);
        }
    }

    /**
     * @notice Updates lending shares for multiple pools.
     * @param poolAddresses Array of lending pool addresses.
     * @param newLendingShares Array of new lending shares.
     */
    function setLendingShares(address[] memory poolAddresses, uint256[] memory newLendingShares) external onlyOwner {
        address poolAddress;
        uint256 newLendingShare;
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            poolAddress = poolAddresses[i];
            newLendingShare = newLendingShares[i];

            totalLendingShares = totalLendingShares - lendingShares[poolAddress] + newLendingShare;
            lendingShares[poolAddress] = newLendingShare;

            emit LendingPoolUpdated(poolAddress, newLendingShare);
        }
    }

    /**
     * @notice Rebalances assets between two lending pools.
     * @param from The address of the lending pool to withdraw from.
     * @param to The address of the lending pool to deposit to.
     * @param sharesToWithdraw The amount of shares to withdraw from the `from` pool.
     */
    function rebalance(address from, address to, uint256 sharesToWithdraw) external onlyOwner {
        require(lendingPoolAddresses.contains(from), "OneClickLending: Invalid 'from' pool address");
        require(lendingPoolAddresses.contains(to), "OneClickLending: Invalid 'to' pool address");

        int256 deviationFrom = _computeDeviation(from);
        int256 deviationTo = _computeDeviation(to);

        require(deviationFrom > 0, "OneClickLending: Pool 'from' not deviated positively");
        require(deviationTo <= 0, "OneClickLending: Pool 'to' not deviated negatively");

        uint256 assets = ILendingPool(from).redeem(sharesToWithdraw, address(this), address(this));

        ILendingPool(to).deposit(assets, address(this));

        deviationFrom = _computeDeviation(from);
        deviationTo = _computeDeviation(to);

        require(deviationFrom >= 0, "OneClickLending: Rebalance failed for 'from' pool");
        require(deviationTo <= 0, "OneClickLending: Rebalance failed for 'to' pool");
    }

    /* ========== VIEW METHODS ========== */

    /**
     * @notice Returns the count of lending pools.
     * @return The number of lending pools.
     */
    function getLendingPoolCount() external view returns (uint256) {
        return lendingPoolAddresses.length();
    }

    /**
     * @notice Returns the total assets managed by the vault.
     * @return The total assets.
     */
    function totalAssets() public view override returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address poolAddress = lendingPoolAddresses.at(i);
            totalBalance += _getBalance(poolAddress);
        }
        return totalBalance;
    }

    /* ========== INTERNAL METHODS ========== */

    /**
     * @notice Computes the deviation of a pool's balance from its target allocation.
     * @param pool The address of the lending pool.
     * @return deviation The deviation of the pool's balance.
     */
    function _computeDeviation(address pool) internal view returns (int256 deviation) {
        uint256 amount = (totalAssets() * lendingShares[pool]) / totalLendingShares;
        deviation = int256(_getBalance(pool)) - int256(amount);
    }

    /**
     * @notice Returns the balance of a lending pool.
     * @param poolAddress The address of the lending pool.
     * @return The balance of the pool.
     */
    function _getBalance(address poolAddress) internal view returns (uint256) {
        return ILendingPool(poolAddress).balanceOf(address(this)) * ILendingPool(poolAddress).sharePrice()
            / 10 ** decimals();
    }

    /**
     * @notice Deposits assets into the lending pools proportionally to their shares.
     * @param assets The amount of assets to deposit.
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
                ILendingPool(poolAddress).deposit(amountToDeposit, address(this));
            }
            if (leftAssets == 0) {
                break;
            }
        }
    }

    /**
     * @notice Redeems shares from the lending pools proportionally.
     * @param shares The amount of shares to redeem.
     * @return assets The amount of assets redeemed.
     */
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        require(lendingPoolAddresses.length() > 0, "OneClickLending: No lending pools available");

        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address poolAddress = lendingPoolAddresses.at(i);
            uint256 poolShareToRedeem = (shares * ILendingPool(poolAddress).balanceOf(address(this))) / totalSupply();
            if (poolShareToRedeem > 0) {
                assets += ILendingPool(poolAddress).redeem(poolShareToRedeem, address(this), address(this));
            }
        }
    }

    /**
     * @notice Validates if a token can be recovered.
     * @param token The address of the token to validate.
     * @return True if the token can be recovered, false otherwise.
     */
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return !lendingPoolAddresses.contains(token);
    }
}
