// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVault, IERC20Metadata, ERC20Upgradeable} from "./BaseVault.sol";
import {IAavePool} from "./interfaces/aave/IPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CErc20} from "./interfaces/compound/IcERC.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract CompoundVault is BaseVault, OwnableUpgradeable {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    CErc20 public immutable pool;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, CErc20 _pool) BaseVault(_asset) {
        pool = _pool;

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol) public initializer {
        IERC20Metadata(super.asset()).forceApprove(address(pool), type(uint256).max);
        __ERC20_init(name, symbol);
        __Ownable_init(admin);
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

    /// @notice It is function only used to withdraw funds accidentally sent to the contract.
    function withdrawFunds(address token) external onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "failed to send ETH");
        } else if (token != address(pool)) {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
        } else {
            revert InvalidTokenToWithdraw(token);
        }
    }
}
