// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/// @title BaseVault
/// @notice Abstract contract for implementing a basic vault structure with fee management
abstract contract BaseVault is ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20Metadata;

    /* ========== ERRORS ========== */

    /// @notice Error thrown when attempting to withdraw an invalid token
    error InvalidTokenToWithdraw(address token);

    /* ========== EVENTS ========== */

    /// @notice Emitted when a deposit is made
    event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares, uint256 depositFee);

    /// @notice Emitted when a withdrawal is made
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint256 fee
    );

    /* ========== CONSTANTS ========== */

    /// @notice Role identifier for managers
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /* ========== IMMUTABLE STATE VARIABLES ========== */

    IERC20Metadata private immutable _asset;
    uint8 private immutable _decimals;

    /// @notice The fee provider contract
    IFeeProvider public immutable feeProvider;

    /// @notice The address that receives the fees
    address public immutable feeRecipient;

    /// @notice The precision used for fee calculations
    uint32 public immutable feePrecision;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice Mapping of account addresses to their deposited balance of assets
    mapping(address account => uint256) internal _depositedBalances;

    /// @notice Mapping of account addresses to their transfer whitelist status
    mapping(address account => bool) public transferWhitelist;

    /* ========== CONSTRUCTOR ========== */

    /// @notice Constructs the BaseVault contract
    /// @param asset_ The underlying asset of the vault
    /// @param _feeProvider The fee provider contract
    /// @param _feeRecipient The address that receives fees
    constructor(IERC20Metadata asset_, IFeeProvider _feeProvider, address _feeRecipient) {
        _asset = asset_;
        _decimals = asset_.decimals();
        if (address(_feeProvider) != address(0)) {
            feeProvider = _feeProvider;
            feeRecipient = _feeRecipient;
            feePrecision = feeProvider.getFeePrecision();
        }
    }

    /* ========== INITIALIZER ========== */

    /// @notice Initializes the BaseVault contract
    /// @param admin The address of the admin
    function __BaseVault_init(address admin, address manager) internal onlyInitializing {
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        transferWhitelist[address(0)] = true;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @notice Pauses the vault
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the vault
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Deposits assets into the vault
    /// @param assets The amount of assets to deposit
    /// @param receiver The address to receive the shares
    /// @return shares The amount of shares minted
    function deposit(uint256 assets, address receiver) public virtual whenNotPaused returns (uint256 shares) {
        if (assets == 0) {
            return 0;
        }
        uint256 totalAssetsBefore = _totalAssetsPrecise();
        _asset.safeTransferFrom(_msgSender(), address(this), assets);
        uint256 depositFee;
        (assets, depositFee) = address(feeProvider) == address(0) ? (assets, 0) : _applyDepositFee(assets);
        _depositedBalances[receiver] += assets;

        _deposit(assets);

        uint256 totalAssetsAfter = _totalAssetsPrecise();
        uint256 increase = totalAssetsAfter - totalAssetsBefore;

        shares = totalAssetsBefore == 0 ? assets : totalSupply() * increase / totalAssetsBefore;

        _mint(receiver, shares);

        emit Deposit(_msgSender(), receiver, assets, shares, depositFee);
    }

    /// @notice Redeems shares from the vault
    /// @param shares The amount of shares to redeem
    /// @param receiver The address to receive the assets
    /// @param owner The owner of the shares
    /// @return assets The amount of assets redeemed
    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        uint256 performanceFee;
        uint256 withdrawalFee;
        assets = _redeem(shares);
        if (address(feeProvider) != address(0)) {
            (assets, performanceFee) = _applyPerformanceFee(assets, shares, owner);
            (assets, withdrawalFee) = _applyWithdrawalFee(assets, owner);
        }

        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, assets, shares, performanceFee + withdrawalFee);
    }

    /// @notice Collects performance fees for multiple accounts
    /// @param accounts The addresses of the accounts to collect fees for
    function collectPerformanceFee(address[] memory accounts) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 assets = getBalanceInUnderlying(accounts[i]);
            if (assets > _depositedBalances[accounts[i]]) {
                uint256 fee = (assets - _depositedBalances[accounts[i]]) * feeProvider.getPerformanceFee(accounts[i])
                    / feePrecision;
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
        } else if (_validateTokenToRecover(token)) {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        } else {
            revert InvalidTokenToWithdraw(token);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Returns the number of decimals of the vault's shares
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Returns the address of the underlying asset
    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    /// @notice Returns the total assets in the vault
    function totalAssets() public view virtual returns (uint256);

    /// @notice Returns the current share price
    function sharePrice() public view virtual returns (uint256) {
        uint256 assets = totalAssets();
        uint256 supply = totalSupply();

        return supply == 0 ? (10 ** _decimals) : assets * (10 ** _decimals) / supply;
    }

    /// @notice Returns the withdrawal fee for an account
    /// @param account The address of the account
    function quoteWithdrawalFee(address account) external view returns (uint256) {
        uint256 assets = getBalanceInUnderlying(account);
        uint256 depositedBalance = _depositedBalances[account];
        uint256 fee;
        if (assets > depositedBalance) {
            fee = (assets - depositedBalance) * feeProvider.getPerformanceFee(account) / feePrecision;
        }

        return fee + ((assets - fee) * feeProvider.getWithdrawalFee(account)) / feePrecision;
    }

    /// @notice Returns the deposited balance of an account
    /// @param account The address of the account
    function getDepositedBalance(address account) external view returns (uint256) {
        return _depositedBalances[account];
    }

    /// @notice Returns the balance in underlying assets of an account
    /// @param account The address of the account
    function getBalanceInUnderlying(address account) public view returns (uint256) {
        return balanceOf(account) * sharePrice() / 10 ** decimals();
    }

    /// @notice Returns the profit of an account
    /// @param account The address of the account
    function getProfit(address account) external view returns (uint256) {
        uint256 balance = getBalanceInUnderlying(account);
        return balance > _depositedBalances[account] ? balance - _depositedBalances[account] : 0;
    }

    /// @notice Returns the deposit fee for an account
    /// @param account The address of the account
    function getDepositFee(address account) external view returns (uint256) {
        return feeProvider.getDepositFee(account);
    }

    /// @notice Returns the withdrawal fee for an account
    /// @param account The address of the account
    function getWithdrawalFee(address account) external view returns (uint256) {
        return feeProvider.getWithdrawalFee(account);
    }

    /// @notice Returns the performance fee for an account
    /// @param account The address of the account
    function getPerformanceFee(address account) external view returns (uint256) {
        return feeProvider.getPerformanceFee(account);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Internal function to deposit assets
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal virtual;

    /// @notice Internal function to redeem shares
    /// @param shares The amount of shares to redeem
    /// @return assets The amount of assets redeemed
    function _redeem(uint256 shares) internal virtual returns (uint256 assets);

    /// @notice Internal function to get the precise total assets
    function _totalAssetsPrecise() internal virtual returns (uint256) {
        return totalAssets();
    }

    /// @notice Applies the deposit fee
    /// @param assets The amount of assets before fee
    /// @return The amount of assets after fee and the fee amount
    function _applyDepositFee(uint256 assets) internal returns (uint256, uint256) {
        uint256 fee = (assets * feeProvider.getDepositFee(msg.sender)) / feePrecision;
        if (fee > 0) {
            assets -= fee;
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee);
        }
        return (assets, fee);
    }

    /// @notice Applies the withdrawal fee
    /// @param assets The amount of assets before fee
    /// @return The amount of assets after fee and the fee amount
    function _applyWithdrawalFee(uint256 assets, address owner) internal returns (uint256, uint256) {
        uint256 fee = (assets * feeProvider.getWithdrawalFee(owner)) / feePrecision;
        if (fee > 0) {
            assets -= fee;
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee);
        }
        return (assets, fee);
    }

    /// @notice Applies the performance fee
    /// @param assets The amount of assets before fee
    /// @param shares The amount of shares being redeemed
    /// @param owner The owner of the shares
    /// @return The amount of assets after fee and the fee amount
    function _applyPerformanceFee(uint256 assets, uint256 shares, address owner) internal returns (uint256, uint256) {
        uint256 balancePortion = _depositedBalances[owner] * shares / balanceOf(owner);
        _depositedBalances[owner] -= balancePortion;
        uint256 fee;
        if (assets > balancePortion) {
            fee = (assets - balancePortion) * feeProvider.getPerformanceFee(owner) / feePrecision;
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee);
        }
        return (assets - fee, fee);
    }

    /// @notice Validates if a token can be recovered
    /// @param token The address of the token to validate
    /// @return Whether the token can be recovered
    function _validateTokenToRecover(address token) internal virtual returns (bool);

    /// @notice Override for update _depositedBalances
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            revert("CYBRO: not whitelisted");
        }
        super._update(from, to, value);
    }
}
