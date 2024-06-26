// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseVault is ERC20 {
    using SafeERC20 for IERC20Metadata;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    IERC20Metadata private immutable _asset;
    uint8 private immutable _decimals;

    constructor(IERC20Metadata asset_) {
        _asset = asset_;
        _decimals = asset_.decimals();
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

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        assets = _redeem(shares);
        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, assets, shares);
    }
}
