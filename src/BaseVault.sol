// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseVault is ERC20Upgradeable {
    using SafeERC20 for IERC20Metadata;

    error InvalidTokenToWithdraw(address token);

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    IERC20Metadata private immutable _asset;
    uint8 private immutable _decimals;
    address public immutable admin;

    constructor(IERC20Metadata asset_) {
        _asset = asset_;
        _decimals = asset_.decimals();
        admin = msg.sender;
    }

    function __BaseVault_init() internal onlyInitializing {}

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

    function _deposit(uint256 assets) internal virtual;

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        if (assets == 0) {
            return 0;
        }
        uint256 totalAssetsBefore = _totalAssetsPrecise();
        _asset.safeTransferFrom(_msgSender(), address(this), assets);

        _deposit(assets);

        uint256 totalAssetsAfter = _totalAssetsPrecise();
        uint256 increase = totalAssetsAfter - totalAssetsBefore;

        shares = totalAssetsBefore == 0 ? assets : totalSupply() * increase / totalAssetsBefore;

        _mint(receiver, shares);

        emit Deposit(_msgSender(), receiver, assets, shares);
    }

    function _redeem(uint256 shares) internal virtual returns (uint256 assets);

    function _redeemBaseVault(uint256 shares, address receiver, address owner) internal returns (uint256 assets) {
        assets = _redeem(shares);
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        return _redeemBaseVault(shares, receiver, owner);
    }

    function _validateTokenToRecover(address token, address poolToken) internal virtual returns (bool) {
        return token != poolToken;
    }

    function emergencyWithdraw(address[] memory accounts) external {
        require(msg.sender == admin, "Only admin");
        for (uint256 i = 0; i < accounts.length; i++) {
            address account = accounts[i];
            uint256 balance = balanceOf(account);
            if (balance > 0) {
                _redeemBaseVault(balance, account, account);
            }
        }
    }
}
