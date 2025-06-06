// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {BaseVault, IERC20Metadata} from "../BaseVault.sol";
import {IJuicePool} from "../interfaces/juice/IJuicePool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract JuiceVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    IJuicePool public immutable pool;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, IJuicePool _pool, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVault(_asset, _feeProvider, _feeRecipient)
    {
        pool = _pool;

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        IERC20Metadata(asset()).forceApprove(address(pool), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        return pool.getDepositAmount(address(this));
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view override returns (uint256) {
        return pool.getTotalSupply();
    }

    /// @inheritdoc BaseVault
    function _deposit(uint256 assets) internal override returns (uint256 totalAssetsBefore) {
        totalAssetsBefore = _totalAssetsPrecise();
        pool.deposit(assets);
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * pool.getDepositAmount(address(this)) / totalSupply();
        pool.withdraw(assets);
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(pool);
    }
}
