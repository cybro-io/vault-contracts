// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";

abstract contract BaseVault is ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20Metadata;

    error InvalidTokenToWithdraw(address token);

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares, uint256 depositFee);

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares,
        uint256 fee
    );

    IERC20Metadata private immutable _asset;
    uint8 private immutable _decimals;

    /// @notice The fee provider contract
    IFeeProvider public immutable feeProvider;

    /// @notice The address that receives the fees
    address public immutable feeRecipient;

    /// @notice The precision used for fee calculations
    uint32 public immutable feePrecision;

    /// @notice Mapping of account addresses to their deposited balance of assets
    mapping(address account => uint256) internal _depositedBalances;

    constructor(IERC20Metadata asset_, IFeeProvider _feeProvider, address _feeRecipient) {
        _asset = asset_;
        _decimals = asset_.decimals();
        if (address(_feeProvider) != address(0)) {
            feeProvider = _feeProvider;
            feeRecipient = _feeRecipient;
            feePrecision = feeProvider.getFeePrecision();
        }
    }

    function __BaseVault_init(address admin) internal onlyInitializing {
        __Ownable_init(admin);
        __Pausable_init();
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    function totalAssets() public view virtual returns (uint256);

    function _totalAssetsPrecise() internal virtual returns (uint256) {
        return totalAssets();
    }

    function sharePrice() public view virtual returns (uint256) {
        uint256 assets = totalAssets();
        uint256 supply = totalSupply();

        return supply == 0 ? (10 ** _decimals) : assets * (10 ** _decimals) / supply;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _deposit(uint256 assets) internal virtual;

    function deposit(uint256 assets, address receiver) public virtual whenNotPaused returns (uint256 shares) {
        if (assets == 0) {
            return 0;
        }
        uint256 totalAssetsBefore = _totalAssetsPrecise();
        _asset.safeTransferFrom(_msgSender(), address(this), assets);
        uint256 depositFee;
        (assets, depositFee) = address(feeProvider) == address(0) ? (assets, 0) : _applyDepositFee(assets);
        _depositedBalances[msg.sender] += assets;

        _deposit(assets);

        uint256 totalAssetsAfter = _totalAssetsPrecise();
        uint256 increase = totalAssetsAfter - totalAssetsBefore;

        shares = totalAssetsBefore == 0 ? assets : totalSupply() * increase / totalAssetsBefore;

        _mint(receiver, shares);

        emit Deposit(_msgSender(), receiver, assets, shares, depositFee);
    }

    function _redeem(uint256 shares) internal virtual returns (uint256 assets);

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        uint256 performanceFee;
        uint256 withdrawalFee;
        assets = _redeem(shares);
        if (address(feeProvider) != address(0)) {
            (assets, performanceFee) = _applyPerformanceFee(assets, shares);
            (assets, withdrawalFee) = _applyWithdrawalFee(assets);
        }

        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, assets, shares, performanceFee + withdrawalFee);
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
        return balanceOf(account) * sharePrice() / 10 ** decimals();
    }

    /// @notice Returns the profit of an account
    /// @param account The address of the account
    /// @return The profit of the account
    function getProfit(address account) external view returns (uint256) {
        uint256 balance = getBalanceInUnderlying(account);
        return balance > _depositedBalances[account] ? balance - _depositedBalances[account] : 0;
    }

    /// @notice Applies the deposit fee
    /// @param assets The amount of assets before fee
    /// @return The amount of assets after fee
    function _applyDepositFee(uint256 assets) internal returns (uint256, uint256) {
        uint256 fee = (assets * feeProvider.getDepositFee(address(msg.sender))) / feePrecision;
        if (fee > 0) {
            assets -= fee;
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee);
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
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee);
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
            IERC20Metadata(_asset).safeTransfer(feeRecipient, fee);
        }
        return (assets - fee, fee);
    }

    function _validateTokenToRecover(address token) internal virtual returns (bool);

    /// @notice It is function only used to withdraw funds accidentally sent to the contract.
    function withdrawFunds(address token) external virtual onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "failed to send ETH");
        } else if (_validateTokenToRecover(token)) {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        } else {
            revert InvalidTokenToWithdraw(token);
        }
    }

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
}
