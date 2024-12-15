// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {BaseVault, IERC20Metadata, ERC20Upgradeable} from "../BaseVault.sol";
import {IAavePool} from "../interfaces/aave/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract AaveVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    IAavePool public immutable pool;
    IERC20 public immutable aToken;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, IAavePool _pool, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVault(_asset, _feeProvider, _feeRecipient)
    {
        pool = _pool;
        aToken = IERC20(pool.getReserveData(address(_asset)).aTokenAddress);

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        IERC20Metadata(asset()).forceApprove(address(pool), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    function totalAssets() public view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function _deposit(uint256 assets) internal override {
        pool.supply(asset(), assets, address(this), 0);
    }

    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * aToken.balanceOf(address(this)) / totalSupply();
        pool.withdraw(asset(), assets, address(this));
    }

    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(aToken);
    }
}
