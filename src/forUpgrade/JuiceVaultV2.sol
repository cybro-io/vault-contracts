// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVaultV2, IERC20Metadata} from "./BaseVaultV2.sol";
import {IJuicePool} from "../interfaces/juice/IJuicePool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract JuiceVaultV2 is BaseVaultV2 {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    IJuicePool public immutable pool;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, IJuicePool _pool, IFeeProvider _feeProvider, address _feeRecipient)
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
        return pool.getDepositAmount(address(this));
    }

    /// @inheritdoc BaseVaultV2
    function underlyingTVL() external view override returns (uint256) {
        return pool.getTotalSupply();
    }

    /// @inheritdoc BaseVaultV2
    function _deposit(uint256 assets) internal override {
        pool.deposit(assets);
    }

    /// @inheritdoc BaseVaultV2
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * pool.getDepositAmount(address(this)) / totalSupply();
        pool.withdraw(assets);
    }

    /// @inheritdoc BaseVaultV2
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(pool);
    }
}
