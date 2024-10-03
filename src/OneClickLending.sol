// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";

/// @title OneClickLending
/// @notice A contract for managing ERC20 token lending to multiple lending pools.
contract OneClickLending is AccessControlUpgradeable, ERC20Upgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* ========== ERRORS ========== */

    /// @notice Thrown when trying to withdraw an invalid token
    error InvalidTokenToWithdraw(address token);

    /* ========== EVENTS ========== */

    /// @notice Emitted when a deposit is made
    /// @param sender The address that initiated the deposit
    /// @param owner The address that owns the deposited assets
    /// @param assets The amount of assets deposited
    /// @param shares The amount of shares minted
    /// @param depositFee The amount of fees paid for the deposit
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares, uint256 depositFee);

    /// @notice Emitted when a withdrawal is made
    /// @param sender The address that initiated the withdrawal
    /// @param receiver The address that received the withdrawn assets
    /// @param owner The address that owned the withdrawn assets
    /// @param assets The amount of assets withdrawn
    /// @param shares The amount of shares burned
    /// @param fee The amount of fees paid for the withdrawal and profit
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint256 fee
    );

    /// @notice Emitted when a new lending pool is added
    /// @param poolAddress The address of the lending pool
    event LendingPoolAdded(address indexed poolAddress);

    /// @notice Emitted when a lending pool is removed
    /// @param poolAddress The address of the removed lending pool
    event LendingPoolRemoved(address indexed poolAddress);

    /// @notice Emitted when a lending pool's share is updated
    /// @param poolAddress The address of the updated lending pool
    /// @param newLendingShare The new share allocated to the lending pool
    event LendingPoolUpdated(address indexed poolAddress, uint256 newLendingShare);

    /* ========== CONSTANTS ========== */

    /// @notice Role identifier for strategists
    bytes32 public constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");

    /// @notice Role identifier for managers
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice Maximum number of lending pools for auto rebalance
    uint256 public constant maxPools = 1000;

    /* ========== IMMUTABLE STATE VARIABLES ========== */

    /// @notice The ERC20 asset managed by the vault
    IERC20Metadata public immutable asset;

    /// @notice The number of decimals of the asset
    uint8 public immutable _decimals;

    /// @notice The fee provider contract
    IFeeProvider public immutable feeProvider;

    /// @notice The address that receives the fees
    address public immutable feeRecipient;

    /// @notice The precision used for fee calculations
    uint32 public immutable feePrecision;

    /* ========== STATE VARIABLES ========== */

    /// @notice Mapping of lending pool addresses to their respective lending shares (in scaled units)
    mapping(address => uint256) public lendingShares;

    /// @notice Set of lending pool addresses
    EnumerableSet.AddressSet private lendingPoolAddresses;

    /// @notice Total lending shares across all pools
    uint256 public totalLendingShares;

    /// @notice Mapping of account addresses to their deposited balance of assets
    mapping(address account => uint256) private _depositedBalances;

    /* ========== CONSTRUCTOR ========== */

    /// @notice Constructor for OneClickLending contract
    /// @param _asset The ERC20 asset managed by the vault
    /// @param _feeProvider The fee provider contract
    /// @param _feeRecipient The address that receives the fees
    constructor(IERC20Metadata _asset, IFeeProvider _feeProvider, address _feeRecipient) {
        asset = _asset;
        _decimals = asset.decimals();
        feeProvider = _feeProvider;
        feeRecipient = _feeRecipient;
        feePrecision = feeProvider.getFeePrecision();
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /// @notice Initializes the contract with admin
    /// @param admin The address of the admin
    function initialize(address admin, string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(STRATEGIST_ROLE, admin);
        _grantRole(MANAGER_ROLE, admin);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Deposits assets into the vault
    /// @param assets The amount of assets to deposit
    /// @return shares The amount of shares minted
    function deposit(uint256 assets) public virtual whenNotPaused returns (uint256 shares) {
        if (assets == 0) {
            return 0;
        }
        uint256 totalAssetsBefore = totalAssets();
        asset.safeTransferFrom(_msgSender(), address(this), assets);
        uint256 depositFee;
        (assets, depositFee) = _applyDepositFee(assets);

        _deposit(assets);

        uint256 totalAssetsAfter = totalAssets();
        uint256 increase = totalAssetsAfter - totalAssetsBefore;

        shares = totalAssetsBefore == 0 ? assets : totalSupply() * increase / totalAssetsBefore;

        _depositedBalances[msg.sender] += assets;
        _mint(msg.sender, shares);

        emit Deposit(_msgSender(), msg.sender, assets, shares, depositFee);
    }

    /// @notice Redeems shares from the vault
    /// @param shares The amount of shares to redeem
    /// @param receiver The address to receive the assets
    /// @return assets The amount of assets redeemed
    function redeem(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        uint256 performanceFee;
        uint256 withdrawalFee;
        (assets, performanceFee) = _applyPerformanceFee(_redeem(shares), shares);
        (assets, withdrawalFee) = _applyWithdrawalFee(assets);
        _burn(msg.sender, shares);
        asset.safeTransfer(receiver, assets);

        emit Withdraw(_msgSender(), receiver, msg.sender, assets, shares, performanceFee + withdrawalFee);
    }

    /// @notice Adds multiple lending pools
    /// @param poolAddresses Array of lending pool addresses
    function addLendingPools(address[] memory poolAddresses) external onlyRole(STRATEGIST_ROLE) {
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            if (lendingPoolAddresses.add(poolAddresses[i])) {
                // Approve the lending pool to use the asset
                asset.forceApprove(address(poolAddresses[i]), type(uint256).max);

                emit LendingPoolAdded(poolAddresses[i]);
            }
        }
    }

    /// @notice Removes multiple lending pools
    /// @param poolAddresses Array of lending pool addresses to remove
    function removeLendingPools(address[] memory poolAddresses) external onlyRole(STRATEGIST_ROLE) {
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            totalLendingShares -= lendingShares[poolAddresses[i]];

            delete lendingShares[poolAddresses[i]];

            require(lendingPoolAddresses.remove(poolAddresses[i]));

            // Revoke approval for the lending pool
            asset.forceApprove(address(poolAddresses[i]), 0);

            emit LendingPoolRemoved(poolAddresses[i]);
        }
    }

    /// @notice Updates lending shares for multiple pools
    /// @param poolAddresses Array of lending pool addresses
    /// @param newLendingShares Array of new lending shares
    function setLendingShares(address[] memory poolAddresses, uint256[] memory newLendingShares)
        external
        onlyRole(MANAGER_ROLE)
    {
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            totalLendingShares = totalLendingShares - lendingShares[poolAddresses[i]] + newLendingShares[i];
            lendingShares[poolAddresses[i]] = newLendingShares[i];

            emit LendingPoolUpdated(poolAddresses[i], newLendingShares[i]);
        }
    }

    /// @notice Rebalances assets between two lending pools
    /// @param from The address of the lending pool to withdraw from
    /// @param to The address of the lending pool to deposit to
    /// @param sharesToWithdraw The amount of shares to withdraw from the `from` pool
    function rebalance(address from, address to, uint256 sharesToWithdraw) external onlyRole(MANAGER_ROLE) {
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

    /// @notice Automatically rebalances assets across all lending pools
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
                uint256 assets = ILendingPool(pool).redeem(
                    uint256(deviation) * ILendingPool(pool).balanceOf(address(this)) / poolBalance,
                    address(this),
                    address(this)
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
                ILendingPool(poolsToDeposit[i]).deposit(depositAmount, address(this));
            }
        }
        if (leftAssets > 0) ILendingPool(poolsToDeposit[count - 1]).deposit(leftAssets, address(this));
    }

    /// @notice Collects performance fees for multiple accounts
    /// @param accounts The addresses of the accounts to collect fees for
    function collectPerformanceFee(address[] memory accounts) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 assets = getBalanceInUnderlying(accounts[i]);
            if (assets > _depositedBalances[accounts[i]]) {
                uint256 fee = (assets - _depositedBalances[accounts[i]])
                    * feeProvider.getPerformanceFee(address(msg.sender)) / feePrecision;
                uint256 feeInShares = fee * 10 ** _decimals / sharePrice();
                _depositedBalances[accounts[i]] = assets - fee;
                super._update(accounts[i], feeRecipient, feeInShares);
            }
        }
    }

    /// @notice Withdraws funds accidentally sent to the contract
    /// @param token The address of the token to withdraw
    function withdrawFunds(address token) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "failed to send ETH");
        } else if (!lendingPoolAddresses.contains(token)) {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        } else {
            revert InvalidTokenToWithdraw(token);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Returns the deposit fee of an account
    /// @param account The address of the account
    /// @return The deposit fee of the account
    function getDepositFee(address account) external view returns (uint256) {
        return feeProvider.getDepositFee(address(account));
    }

    /// @notice Returns the withdrawal fee of an account
    /// @param account The address of the account
    /// @return The withdrawal fee of the account
    function getWithdrawalFee(address account) external view returns (uint256) {
        return feeProvider.getWithdrawalFee(address(account));
    }

    /// @notice Returns the performance fee of an account
    /// @param account The address of the account
    /// @return The performance fee of the account
    function getPerformanceFee(address account) external view returns (uint256) {
        return feeProvider.getPerformanceFee(address(account));
    }

    /// @notice Returns the share price of a lending pool
    /// @param pool The address of the lending pool
    /// @return The share price of the pool
    function getSharePriceOfPool(address pool) external view returns (uint256) {
        return ILendingPool(pool).sharePrice();
    }

    /// @notice Returns the balance of a lending pool
    /// @param pool The address of the lending pool
    /// @return The balance of the pool
    function getBalanceOfPool(address pool) external view returns (uint256) {
        return ILendingPool(pool).balanceOf(address(this)) * ILendingPool(pool).sharePrice() / 10 ** _decimals;
    }

    /// @notice Returns the deposited balance of an account
    /// @param account The address of the account
    /// @return The deposited balance of the account
    function getDepositedBalance(address account) external view returns (uint256) {
        return _depositedBalances[account];
    }

    /// @notice Returns the balance in underlying of an account
    /// @param account The address of the account
    /// @return The balance in underlying of the account
    function getBalanceInUnderlying(address account) public view returns (uint256) {
        return balanceOf(account) * sharePrice() / 10 ** _decimals;
    }

    /// @notice Returns the profit of an account
    /// @param account The address of the account
    /// @return The profit of the account
    function getProfit(address account) external view returns (uint256) {
        uint256 balance = getBalanceInUnderlying(account);
        return balance > _depositedBalances[account] ? balance - _depositedBalances[account] : 0;
    }

    /// @notice Returns the withdrawal fee of an account
    /// @param account The address of the account
    /// @return The withdrawal fee of the account
    function quoteWithdrawalFee(address account) external view returns (uint256) {
        uint256 assets = getBalanceInUnderlying(account);
        uint256 depositedBalance = _depositedBalances[account];
        uint256 fee;
        if (assets > depositedBalance) {
            fee = (assets - depositedBalance) * feeProvider.getPerformanceFee(address(msg.sender)) / feePrecision;
        }

        return fee + ((assets - fee) * feeProvider.getWithdrawalFee(address(msg.sender))) / feePrecision;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Returns array of all lending pools
    /// @return Array of lending pools
    function getPools() external view returns (address[] memory) {
        return lendingPoolAddresses.values();
    }

    /// @notice Returns the count of lending pools
    /// @return The number of lending pools
    function getLendingPoolCount() external view returns (uint256) {
        return lendingPoolAddresses.length();
    }

    /// @notice Returns the total assets managed by the vault
    /// @return The total assets
    function totalAssets() public view returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address poolAddress = lendingPoolAddresses.at(i);
            totalBalance += _getBalance(poolAddress);
        }
        return totalBalance;
    }

    /// @notice Calculates the current share price
    /// @return The current share price
    function sharePrice() public view virtual returns (uint256) {
        uint256 assets = totalAssets();
        uint256 supply = totalSupply();

        return supply == 0 ? (10 ** _decimals) : assets * (10 ** _decimals) / supply;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Override for transfer restriction
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            revert("OneClickLending: Transfer not allowed");
        }
        super._update(from, to, value);
    }

    /// @notice Computes the deviation of a pool's balance from its target allocation
    /// @param pool The address of the lending pool
    /// @return deviation The deviation of the pool's balance
    function _computeDeviation(address pool) internal view returns (int256 deviation) {
        uint256 amount = (totalAssets() * lendingShares[pool]) / totalLendingShares;
        deviation = int256(_getBalance(pool)) - int256(amount);
    }

    /// @notice Returns the balance of a lending pool
    /// @param poolAddress The address of the lending pool
    /// @return The balance of the pool
    function _getBalance(address poolAddress) internal view returns (uint256) {
        return ILendingPool(poolAddress).balanceOf(address(this)) * ILendingPool(poolAddress).sharePrice()
            / 10 ** _decimals;
    }

    /// @notice Deposits assets into the lending pools proportionally to their shares
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal {
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

    /// @notice Redeems shares from the lending pools proportionally
    /// @param shares The amount of shares to redeem
    /// @return assets The amount of assets redeemed
    function _redeem(uint256 shares) internal returns (uint256 assets) {
        require(lendingPoolAddresses.length() > 0, "OneClickLending: No lending pools available");

        for (uint256 i = 0; i < lendingPoolAddresses.length(); i++) {
            address poolAddress = lendingPoolAddresses.at(i);
            uint256 poolShareToRedeem = (shares * ILendingPool(poolAddress).balanceOf(address(this))) / totalSupply();
            if (poolShareToRedeem > 0) {
                assets += ILendingPool(poolAddress).redeem(poolShareToRedeem, address(this), address(this));
            }
        }
    }

    /// @notice Applies the deposit fee
    /// @param assets The amount of assets before fee
    /// @return The amount of assets after fee
    function _applyDepositFee(uint256 assets) internal returns (uint256, uint256) {
        uint256 fee = (assets * feeProvider.getDepositFee(address(msg.sender))) / feePrecision;
        if (fee > 0) {
            assets -= fee;
            asset.safeTransfer(feeRecipient, fee);
        }
        return (assets, fee);
    }

    /// @notice Applies the withdrawal fee
    /// @param assets The amount of assets before fee
    /// @return The amount of assets after fee
    function _applyWithdrawalFee(uint256 assets) internal returns (uint256, uint256) {
        uint256 fee = (assets * feeProvider.getWithdrawalFee(address(msg.sender))) / feePrecision;
        if (fee > 0) {
            assets -= fee;
            asset.safeTransfer(feeRecipient, fee);
        }
        return (assets, fee);
    }

    /// @notice Applies the performance fee
    /// @param assets The amount of assets before fee
    /// @param shares The amount of shares being redeemed
    /// @return The amount of assets after fee
    function _applyPerformanceFee(uint256 assets, uint256 shares) internal returns (uint256, uint256) {
        uint256 balancePortion = _depositedBalances[msg.sender] * shares / balanceOf(msg.sender);
        _depositedBalances[msg.sender] -= balancePortion;
        uint256 fee;
        if (assets > balancePortion) {
            fee = (assets - balancePortion) * feeProvider.getPerformanceFee(address(msg.sender)) / feePrecision;
            asset.safeTransfer(feeRecipient, fee);
        }
        return (assets - fee, fee);
    }
}
