// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVault, IERC20Metadata, ERC20} from "./BaseVault.sol";
import {IAavePool} from "./interfaces/aave/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CErc20} from "./interfaces/compound/IcERC.sol";

contract CompoundVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    CErc20 public immutable pool;

    constructor(IERC20Metadata _asset, CErc20 _pool, string memory name, string memory symbol)
        BaseVault(_asset)
        ERC20(name, symbol)
    {
        pool = _pool;
        _asset.forceApprove(address(pool), type(uint256).max);
    }

    function totalAssets() public view override returns (uint256) {
        return pool.balanceOf(address(this)) * pool.exchangeRateStored() / 1e18;
    }

    function _totalAssetsPrecise() internal override returns (uint256) {
        return pool.balanceOfUnderlying(address(this));
    }

    function _deposit(uint256 assets) internal override {
        require(pool.mint(assets) == 0, "Pool Error");
    }

    function _redeem(uint256 shares) internal override returns (uint256 underlyingAssets) {
        uint256 balanceBefore = IERC20Metadata(super.asset()).balanceOf(address(this));
        require(pool.redeem(shares * pool.balanceOf(address(this)) / totalSupply()) == 0, "Pool Error");
        underlyingAssets = IERC20Metadata(super.asset()).balanceOf(address(this)) - balanceBefore;
    }
}
