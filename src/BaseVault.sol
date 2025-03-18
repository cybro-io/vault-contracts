// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {IVault} from "./interfaces/IVault.sol";

/**
 * @title BaseVault
 * @notice Abstract contract for implementing a basic vault structure with fee management
 */
abstract contract BaseVault is ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable, IVault {
    using SafeERC20 for IERC20Metadata;

    /// @custom:storage-location erc7201:cybro.storage.BaseVault
    struct BaseVaultStorage {
        mapping(address account => uint256) waterline;
        uint256 lastTimeManagementFeeCollected;
    }

    function _getBaseVaultStorage() private pure returns (BaseVaultStorage storage $) {
        assembly {
            $.slot := BASE_VAULT_STORAGE_LOCATION
        }
    }

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when a deposit is made
     * @param sender The address of the sender
     * @param receiver The address of the receiver
     * @param assets The amount of assets deposited
     * @param shares The amount of shares minted
     * @param depositFee The amount of deposit fee
     * @param totalSupplyBefore The total supply before the deposit
     * @param tvlBefore The total value locked before the deposit
     */
    event Deposit(
        address indexed sender,
        address indexed receiver,
        uint256 assets,
        uint256 shares,
        uint256 depositFee,
        uint256 totalSupplyBefore,
        uint256 tvlBefore
    );

    /**
     * @notice Emitted when a withdrawal is made
     * @param sender The address of the sender
     * @param receiver The address of the receiver
     * @param owner The address of the owner
     * @param assets The amount of assets withdrawn
     * @param shares The amount of shares withdrawn
     * @param withdrawalFee The amount of withdrawal fee
     * @param totalSupplyBefore The total supply before the withdrawal
     * @param tvlBefore The total value locked before the withdrawal
     */
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 shares,
        uint256 assets,
        uint256 withdrawalFee,
        uint256 totalSupplyBefore,
        uint256 tvlBefore
    );

    /**
     * @notice Emitted when performance fee is collected
     * @param owner The address of the user who is being charged
     * @param fee The amount of fee collected
     */
    event PerformanceFeeCollected(address indexed owner, uint256 fee);

    /**
     * @notice Emitted when management fee is collected
     * @param shares The amount of shares minted
     */
    event ManagementFeeCollected(uint256 shares);

    /* ========== CONSTANTS ========== */

    // keccak256(abi.encode(uint256(keccak256("cybro.storage.BaseVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASE_VAULT_STORAGE_LOCATION =
        0x3723283c6c153be31b346222d4cdfc82d474472705dbc1bceef0b3066f389b00;

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

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructs the BaseVault contract
     * @param asset_ The underlying asset of the vault
     * @param _feeProvider The fee provider contract
     * @param _feeRecipient The address that receives fees
     */
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

    /**
     * @notice Initializes the BaseVault contract
     * @param admin The address of the admin
     * @param manager The address of the manager
     */
    function __BaseVault_init(address admin, address manager) internal onlyInitializing {
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        $.lastTimeManagementFeeCollected = block.timestamp;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Pauses the vault
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the vault
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Deposits assets into the vault
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the shares
     * @param minShares The minimum amount of shares to mint
     * @return shares The amount of shares minted
     */
    function deposit(uint256 assets, address receiver, uint256 minShares)
        public
        virtual
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) {
            return 0;
        }
        uint256 totalAssetsBefore = _totalAssetsPrecise();
        uint256 totalSupplyBefore = totalSupply();
        _asset.safeTransferFrom(_msgSender(), address(this), assets);
        uint256 depositFee;
        (assets, depositFee) = address(feeProvider) == address(0) ? (assets, 0) : _applyDepositFee(assets);

        _deposit(assets);

        uint256 totalAssetsAfter = _totalAssetsPrecise();
        uint256 increase = totalAssetsAfter - totalAssetsBefore;

        shares = (totalAssetsBefore == 0 || totalSupplyBefore == 0)
            ? increase
            : totalSupplyBefore * increase / totalAssetsBefore;

        require(shares >= minShares, "minShares");

        BaseVaultStorage storage $ = _getBaseVaultStorage();
        $.waterline[receiver] += increase;
        _mint(receiver, shares);

        emit Deposit(_msgSender(), receiver, increase, shares, depositFee, totalSupplyBefore, totalAssetsBefore);
    }

    /**
     * @notice Deposits assets with an updated fee discount based on staking amount
     * @dev Updates the user's staked amount before performing the deposit to apply the correct fee discount
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the shares
     * @param minShares The minimum amount of shares to mint (slippage protection)
     * @param stakedAmount The amount of tokens staked by the user
     * @param deadline The deadline for the signature to be valid
     * @param signature The signature from the authorized signer verifying the staked amount
     * @return shares The amount of shares minted to the receiver
     */
    function updateFeeDiscountDeposit(
        uint256 assets,
        address receiver,
        uint256 minShares,
        uint256 stakedAmount,
        uint256 deadline,
        bytes memory signature
    ) external returns (uint256 shares) {
        feeProvider.setStakedAmount(msg.sender, stakedAmount, deadline, signature);
        return deposit(assets, receiver, minShares);
    }

    /**
     * @notice Redeems shares from the vault
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @param minAssets The minimum amount of assets to receive
     * @return assets The amount of assets redeemed
     */
    function redeem(uint256 shares, address receiver, address owner, uint256 minAssets)
        public
        virtual
        returns (uint256 assets)
    {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }
        assets = _redeemBaseVault(shares, receiver, owner);
        require(assets >= minAssets, "CYBRO: minAssets");
    }

    /**
     * @notice Collects performance fees for multiple accounts
     * @param accounts The addresses of the accounts to collect fees for
     */
    function collectPerformanceFee(address[] memory accounts) external onlyRole(MANAGER_ROLE) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 assets = getBalanceInUnderlying(accounts[i]);
            if (assets > $.waterline[accounts[i]]) {
                uint256 fee =
                    (assets - $.waterline[accounts[i]]) * feeProvider.getPerformanceFee(accounts[i]) / feePrecision;
                $.waterline[accounts[i]] = assets - fee;
                emit PerformanceFeeCollected(accounts[i], fee);
                super._update(accounts[i], feeRecipient, fee * 10 ** _decimals / sharePrice());
            }
        }
    }

    /**
     * @notice Collects annual management fee, pro-rated based on time passed since last collection
     *
     * For example, if:
     * - Annual managementFee is 10% (100 in feePrecision units)
     * - Total supply is 1000
     * - 6 months (182.5 days) passed since last collection
     * Then:
     * shares = 1000 * 100 * (182.5 days) / 365 days / (1000 - 100)
     * ≈ 1000 * 100 * 0.5 / 900 ≈ 55.56
     *
     * The fee is calculated proportionally to the exact time passed since last collection,
     * using 365 days as the base period for the annual rate.
     */
    function collectManagementFee() external onlyRole(MANAGER_ROLE) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint32 managementFee = feeProvider.getManagementFee();
        uint256 shares = totalSupply() * managementFee * (block.timestamp - $.lastTimeManagementFeeCollected) / 365 days
            / (feePrecision - managementFee);
        $.lastTimeManagementFeeCollected = block.timestamp;
        _mint(feeRecipient, shares);
        emit ManagementFeeCollected(shares);
    }

    function emergencyWithdraw(address[] memory accounts) external onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 balance = balanceOf(account);
            if (balance > 0) {
                _redeemBaseVault(balance, account, account);
            }
        }
    }

    /**
     * @notice Withdraws funds accidentally sent to the contract
     * @param token The address of the token to withdraw
     */
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

    /**
     * @notice Returns the number of decimals of the vault's shares
     * @return The number of decimals
     */
    function decimals() public view override(IERC20Metadata, ERC20Upgradeable) returns (uint8) {
        return _decimals;
    }

    /**
     * @notice Returns the address of the underlying asset
     * @return The address of the asset
     */
    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    /**
     * @notice Returns the total assets in the vault
     * @return The total assets
     */
    function totalAssets() public view virtual returns (uint256);

    /**
     * @notice Returns the current share price
     * @return The share price
     */
    function sharePrice() public view virtual returns (uint256) {
        uint256 assets = totalAssets();
        uint256 supply = totalSupply();

        return supply == 0 ? (10 ** _decimals) : assets * (10 ** _decimals) / supply;
    }

    /**
     * @notice Returns the sum of the withdrawal fee and performance fee for an account
     * that will be charged during the redeem process
     * @param account The address of the account
     * @return The withdrawal fee
     */
    function quoteWithdrawalFee(address account) external view returns (uint256) {
        if (address(feeProvider) == address(0)) {
            return 0;
        }
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint256 assets = getBalanceInUnderlying(account);
        uint256 waterline = $.waterline[account];
        uint256 fee_;
        if (assets > waterline) {
            fee_ = (assets - waterline) * feeProvider.getPerformanceFee(account) / feePrecision;
        }

        return fee_ + ((assets - fee_) * feeProvider.getWithdrawalFee(account)) / feePrecision;
    }

    /**
     * @notice Returns the waterline of an account
     * @param account The address of the account
     * @return The waterline
     */
    function getWaterline(address account) external view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.waterline[account];
    }

    /**
     * @notice Returns the balance in underlying assets of an account
     * @param account The address of the account
     * @return The balance in underlying assets
     */
    function getBalanceInUnderlying(address account) public view returns (uint256) {
        return balanceOf(account) * sharePrice() / 10 ** decimals();
    }

    /**
     * @notice Returns the profit of an account
     * @param account The address of the account
     * @return The profit
     */
    function getProfit(address account) external view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint256 balance = getBalanceInUnderlying(account);
        return balance > $.waterline[account] ? balance - $.waterline[account] : 0;
    }

    /**
     * @notice Returns the total value locked (TVL) in the underlying vault where this vault deposits its assets
     * @dev This value represents the TVL of the destination vault, not the TVL of this vault itself
     * @return The total value locked in the underlying vault, expressed in the underlying asset's decimals
     */
    function underlyingTVL() external view virtual returns (uint256);

    /**
     * @notice Returns the deposit fee for an account
     * @param account The address of the account
     * @return The deposit fee
     */
    function getDepositFee(address account) external view returns (uint32) {
        return feeProvider.getDepositFee(account);
    }

    /**
     * @notice Returns the withdrawal fee for an account
     * @param account The address of the account
     * @return The withdrawal fee
     */
    function getWithdrawalFee(address account) external view returns (uint32) {
        return feeProvider.getWithdrawalFee(account);
    }

    /**
     * @notice Returns the performance fee for an account
     * @param account The address of the account
     * @return The performance fee
     */
    function getPerformanceFee(address account) external view returns (uint32) {
        return feeProvider.getPerformanceFee(account);
    }

    /**
     * @notice Returns the management fee
     * @return The management fee
     */
    function getManagementFee() external view returns (uint32) {
        return feeProvider.getManagementFee();
    }

    function getLastTimeManagementFeeCollected() external view returns (uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        return $.lastTimeManagementFeeCollected;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Internal function to deposit assets
     * @param assets The amount of assets to deposit
     */
    function _deposit(uint256 assets) internal virtual;

    /**
     * @notice Internal function to redeem shares
     * @param shares The amount of shares to redeem
     * @return assets The amount of assets redeemed
     */
    function _redeem(uint256 shares) internal virtual returns (uint256 assets);

    /**
     * @notice Internal function to redeem shares
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive the assets
     * @param owner The owner of the shares
     * @return assets The amount of assets redeemed
     */
    function _redeemBaseVault(uint256 shares, address receiver, address owner) internal returns (uint256 assets) {
        uint256 withdrawalFee;
        uint256 tvlBefore = _totalAssetsPrecise();
        uint256 totalSupplyBefore = totalSupply();
        assets = _redeem(shares);
        if (address(feeProvider) != address(0)) {
            (assets,) = _applyPerformanceFee(assets, shares, owner);
            (assets, withdrawalFee) = _applyWithdrawalFee(assets, owner);
        }

        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, shares, assets, withdrawalFee, totalSupplyBefore, tvlBefore);
    }

    /**
     * @notice Internal function to get the precise total assets
     * @return The precise total assets
     */
    function _totalAssetsPrecise() internal virtual returns (uint256) {
        return totalAssets();
    }

    /**
     * @notice Applies the deposit fee
     * @param assets The amount of assets before fee
     * @return The amount of assets after fee and the fee amount
     */
    function _applyDepositFee(uint256 assets) internal returns (uint256, uint256) {
        (uint256 fee_,,) = feeProvider.getUpdateUserFees(msg.sender);
        fee_ = (assets * fee_) / feePrecision;
        if (fee_ > 0) {
            assets -= fee_;
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee_);
        }
        return (assets, fee_);
    }

    /**
     * @notice Applies the withdrawal fee
     * @param assets The amount of assets before fee
     * @param owner The owner of the shares
     * @return The amount of assets after fee and the fee amount
     */
    function _applyWithdrawalFee(uint256 assets, address owner) internal returns (uint256, uint256) {
        uint256 fee_ = (assets * feeProvider.getWithdrawalFee(owner)) / feePrecision;
        if (fee_ > 0) {
            assets -= fee_;
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee_);
        }
        return (assets, fee_);
    }

    /**
     * @notice Applies the performance fee
     * @param assets The amount of assets before fee
     * @param shares The amount of shares being redeemed
     * @param owner The owner of the shares
     * @return The amount of assets after fee and the fee amount
     */
    function _applyPerformanceFee(uint256 assets, uint256 shares, address owner) internal returns (uint256, uint256) {
        BaseVaultStorage storage $ = _getBaseVaultStorage();
        uint256 balancePortion = $.waterline[owner] * shares / balanceOf(owner);
        $.waterline[owner] -= balancePortion;
        uint256 fee_;
        if (assets > balancePortion) {
            fee_ = (assets - balancePortion) * feeProvider.getPerformanceFee(owner) / feePrecision;
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee_);
            emit PerformanceFeeCollected(owner, fee_);
        }
        return (assets - fee_, fee_);
    }

    /**
     * @notice Validates if a token can be recovered
     * @param token The address of the token to validate
     * @return Whether the token can be recovered
     */
    function _validateTokenToRecover(address token) internal virtual returns (bool);

    /**
     * @notice Override for transfer restriction
     * @param from The sender address
     * @param to The receiver address
     * @param value The amount transferred
     */
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            revert("CYBRO: Transfer not allowed");
        }
        super._update(from, to, value);
    }
}
