// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IERC20Metadata, BaseVaultV2} from "./BaseVaultV2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CEth} from "../interfaces/compound/IcETH.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract CompoundVaultETHV2 is BaseVaultV2 {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    CEth public immutable pool;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, CEth _pool, IFeeProvider _feeProvider, address _feeRecipient)
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

    /**
     * @notice Wraps native ETH into WETH.
     * @param amount The amount of ETH to wrap
     */
    function _wrapETH(uint256 amount) internal {
        IWETH(address(asset())).deposit{value: amount}();
    }

    /**
     * @notice Unwraps WETH into ETH.
     * @param amount The amount of WETH to unwrap
     */
    function _unwrapETH(uint256 amount) internal {
        IWETH(address(asset())).withdraw(amount);
    }

    /// @inheritdoc BaseVaultV2
    function _redeem(uint256 shares) internal override returns (uint256 underlyingAssets) {
        uint256 balanceBefore = address(this).balance;
        require(pool.redeem(shares * pool.balanceOf(address(this)) / totalSupply()) == 0, "Pool Error");
        underlyingAssets = address(this).balance - balanceBefore;
        _wrapETH(underlyingAssets);
    }

    /// @inheritdoc BaseVaultV2
    function _deposit(uint256 assets) internal virtual override {
        _unwrapETH(assets);
        pool.mint{value: assets}();
    }

    /// @inheritdoc BaseVaultV2
    function _totalAssetsPrecise() internal virtual override returns (uint256) {
        return pool.balanceOfUnderlying(address(this));
    }

    /// @inheritdoc BaseVaultV2
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(pool);
    }

    receive() external payable {
        require(msg.sender == address(pool) || msg.sender == asset());
    }
}
