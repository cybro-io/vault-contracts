// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IERC20Metadata, BaseVault, ERC20} from "./BaseVault.sol";
import {IAavePool} from "./interfaces/aave/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CEth} from "./interfaces/compound/IcETH.sol";
import {IWETH} from "./interfaces/IWETH.sol";

contract CompoundVaultETH is BaseVault {
    using SafeERC20 for IERC20Metadata;

    CEth public immutable pool;

    constructor(IERC20Metadata _asset, CEth _pool, string memory name, string memory symbol)
        BaseVault(_asset)
        ERC20(name, symbol)
    {
        pool = _pool;
    }

    function totalAssets() public view override returns (uint256) {
        return pool.balanceOf(address(this)) * pool.exchangeRateStored() / 1e18;
    }

    /// @notice Wraps native ETH into WETH.
    function _wrapETH(uint256 amount) internal {
        IWETH(address(super.asset())).deposit{value: amount}();
    }

    /// @notice Unwraps WETH into ETH.
    function _unwrapETH(uint256 amount) internal {
        IWETH(address(super.asset())).withdraw(amount);
    }

    function _redeem(uint256 shares) internal override returns (uint256 underlyingAssets) {
        uint256 balanceBefore = address(this).balance;
        require(pool.redeem(shares * pool.balanceOf(address(this)) / totalSupply()) == 0, "Pool Error");
        underlyingAssets = address(this).balance - balanceBefore;
        _wrapETH(underlyingAssets);
    }

    function _deposit(uint256 assets) internal virtual override {
        _unwrapETH(assets);
        pool.mint{value: assets}();
    }

    function _totalAssetsPrecise() internal virtual override returns (uint256) {
        return pool.balanceOfUnderlying(address(this));
    }

    receive() external payable {
        require(msg.sender == address(pool) || msg.sender == super.asset());
    }
}
