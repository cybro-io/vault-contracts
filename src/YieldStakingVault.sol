// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IYieldStaking} from "./interfaces/IYieldStaking.sol";
import {BaseVault, IERC20Metadata, ERC20Upgradeable} from "./BaseVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Test, console} from "forge-std/Test.sol";

contract YieldStakingVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    IYieldStaking public immutable staking;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, IYieldStaking _staking) BaseVault(_asset) {
        staking = _staking;

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol) public initializer {
        IERC20Metadata(asset()).forceApprove(address(staking), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 balance, uint256 rewards) = staking.balanceAndRewards(asset(), address(this));
        return balance + rewards;
    }

    function _deposit(uint256 assets) internal override {
        staking.stake(asset(), assets);
    }

    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        (uint256 balance, uint256 rewards) = staking.balanceAndRewards(asset(), address(this));
        assets = shares * (balance + rewards) / totalSupply();
        if (rewards < assets) {
            staking.claimReward(asset(), asset(), rewards, false, bytes(""), 0);
            staking.withdraw(asset(), assets - rewards, false);
        } else {
            staking.claimReward(asset(), asset(), assets, false, bytes(""), 0);
        }
    }

    function _validateTokenToRecover(address) internal virtual override returns (bool) {
        return true;
    }
}
