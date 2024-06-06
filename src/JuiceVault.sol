// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVault, IERC20Metadata, ERC20} from "./BaseVault.sol";
import {IJuicePool} from "./interfaces/juice/IJuicePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract JuiceVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    IJuicePool public immutable pool;
    IERC20 public immutable aToken;

    constructor(IERC20Metadata _asset, IJuicePool _pool, string memory name, string memory symbol)
        BaseVault(_asset)
        ERC20(name, symbol)
    {
        pool = _pool;
        aToken = IERC20(pool.liquidityToken());
        _asset.forceApprove(address(pool), type(uint256).max);
    }

    function totalAssets() public view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function _deposit(uint256 assets) internal override {
        pool.deposit(assets);
    }

    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * aToken.balanceOf(address(this)) / totalSupply();
        pool.withdraw(assets);
    }
}
