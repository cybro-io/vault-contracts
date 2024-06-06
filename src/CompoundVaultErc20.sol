// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVault, IERC20Metadata, ERC20} from "./BaseVault.sol";
import {IAavePool} from "./interfaces/aave/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CErc20} from "./interfaces/compound/IcERC.sol";

contract CompoundVault is ERC20 {
    using SafeERC20 for IERC20Metadata;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    CErc20 public immutable pool;
    IERC20Metadata private immutable _asset;
    uint8 private immutable _decimals;

    constructor(IERC20Metadata asset_, CErc20 _pool, string memory name, string memory symbol) ERC20(name, symbol) {
        _asset = asset_;
        _decimals = _asset.decimals();
        pool = _pool;
        _asset.forceApprove(address(pool), type(uint256).max);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function asset() public view virtual returns (address) {
        return address(_asset);
    }

    function sharePrice() public view virtual returns (uint256) {
        uint256 assets = totalAssets();
        uint256 supply = totalSupply();

        return supply == 0 ? (10 ** _decimals) : assets * (10 ** _decimals) / supply;
    }

    function _totalAssetsPrecise() internal returns (uint256) {
        return pool.balanceOfUnderlying(address(this));
    }

    function totalAssets() public view returns (uint256) {
        return pool.balanceOf(address(this)) * pool.exchangeRateStored() / 1e18;
    }

    function _deposit(uint256 assets) internal {
        require(pool.mint(assets) == 0, "Pool Error");
    }

    function _redeem(uint256 shares) internal {
        require(pool.redeem(shares * pool.balanceOf(address(this)) / totalSupply()) == 0, "Pool Error");
    }

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

    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        returns (uint256 underlyingAssets)
    {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        underlyingAssets = shares * _totalAssetsPrecise() / totalSupply();
        _redeem(shares);
        _burn(owner, shares);
        _asset.safeTransfer(receiver, underlyingAssets);

        emit Withdraw(_msgSender(), receiver, owner, underlyingAssets, shares);
    }
}
