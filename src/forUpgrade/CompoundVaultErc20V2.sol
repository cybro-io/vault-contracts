// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVaultV2, IERC20Metadata} from "./BaseVaultV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CErc20} from "../interfaces/compound/IcERC.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract CompoundVaultV2 is BaseVaultV2 {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    CErc20 public immutable pool;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, CErc20 _pool, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVaultV2(_asset, _feeProvider, _feeRecipient)
    {
        pool = _pool;

        _disableInitializers();
    }

    function initialize() public reinitializer(2) {
        __BaseVault_init(msg.sender, msg.sender);
    }

    /// @inheritdoc BaseVaultV2
    function totalAssets() public view override returns (uint256) {
        return pool.balanceOf(address(this)) * pool.exchangeRateStored() / 1e18;
    }

    /// @inheritdoc BaseVaultV2
    function underlyingTVL() external view virtual override returns (uint256) {
        return pool.totalSupply() * pool.exchangeRateStored() / 1e18;
    }

    /// @inheritdoc BaseVaultV2
    function _totalAssetsPrecise() internal override returns (uint256) {
        return pool.balanceOfUnderlying(address(this));
    }

    /// @inheritdoc BaseVaultV2
    function _deposit(uint256 assets) internal override {
        require(pool.mint(assets) == 0, "Pool Error");
    }

    /// @inheritdoc BaseVaultV2
    function _redeem(uint256 shares) internal override returns (uint256 underlyingAssets) {
        uint256 balanceBefore = IERC20Metadata(asset()).balanceOf(address(this));
        require(pool.redeem(shares * pool.balanceOf(address(this)) / totalSupply()) == 0, "Pool Error");
        underlyingAssets = IERC20Metadata(asset()).balanceOf(address(this)) - balanceBefore;
    }

    /// @inheritdoc BaseVaultV2
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(pool);
    }
}
