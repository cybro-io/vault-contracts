// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {BaseVaultV2, IERC20Metadata} from "./BaseVaultV2ForOneClick_InsideVaults.sol";
import {IAavePool} from "../interfaces/aave/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract AaveVaultV2_InsideOneClickIndex is BaseVaultV2 {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    IAavePool public immutable pool;
    IERC20 public immutable aToken;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, IAavePool _pool, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVaultV2(_asset, _feeProvider, _feeRecipient)
    {
        pool = _pool;
        aToken = IERC20(pool.getReserveData(address(_asset)).aTokenAddress);

        _disableInitializers();
    }

    function initialize() public reinitializer(2) {
        __BaseVault_init();
    }

    /// @inheritdoc BaseVaultV2
    function totalAssets() public view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /// @inheritdoc BaseVaultV2
    function underlyingTVL() external view virtual override returns (uint256) {
        return aToken.totalSupply();
    }

    /// @inheritdoc BaseVaultV2
    function _deposit(uint256 assets) internal override {
        pool.supply(asset(), assets, address(this), 0);
    }

    /// @inheritdoc BaseVaultV2
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * aToken.balanceOf(address(this)) / totalSupply();
        pool.withdraw(asset(), assets, address(this));
    }

    /// @inheritdoc BaseVaultV2
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(aToken);
    }
}
