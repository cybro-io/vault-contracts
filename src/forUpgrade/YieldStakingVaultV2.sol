// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IYieldStaking} from "../interfaces/blastup/IYieldStacking.sol";
import {BaseVaultV2, IERC20Metadata} from "./BaseVaultV2.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

/// @title YieldStakingVault
contract YieldStakingVaultV2 is BaseVaultV2 {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    /// @notice The Yield Staking contract
    IYieldStaking public immutable staking;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, IYieldStaking _staking, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVaultV2(_asset, _feeProvider, _feeRecipient)
    {
        staking = _staking;

        _disableInitializers();
    }

    function initialize() public reinitializer(2) {
        __BaseVault_init(msg.sender, msg.sender);
    }

    /// @inheritdoc BaseVaultV2
    function totalAssets() public view override returns (uint256) {
        (uint256 balance, uint256 rewards) = staking.balanceAndRewards(asset(), address(this));
        return balance + rewards;
    }

    /// @inheritdoc BaseVaultV2
    function underlyingTVL() external view virtual override returns (uint256) {
        return staking.totalSupply(asset());
    }

    /// @inheritdoc BaseVaultV2
    function _deposit(uint256 assets) internal override {
        staking.stake(asset(), assets);
    }

    /// @inheritdoc BaseVaultV2
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

    /// @inheritdoc BaseVaultV2
    function _validateTokenToRecover(address) internal virtual override returns (bool) {
        return true;
    }
}
