// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {BaseVault} from "./BaseVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title ERC4626Mixin
 * @notice This mixin is used to implement the ERC4626 interface.
 */
abstract contract ERC4626Mixin is BaseVault {
    using SafeERC20 for IERC20Metadata;

    error NotImplemented();
    error PerformanceFeeNotZero();

    /// @custom:storage-location erc7201:cybro.storage.ERC4626Mixin
    struct ERC4626MixinStorage {
        uint32 maxSlippageForPreview;
    }

    function _getERC4626MixinStorage() private pure returns (ERC4626MixinStorage storage $) {
        assembly {
            $.slot := ERC4626_MIXIN_STORAGE_LOCATION
        }
    }

    // keccak256(abi.encode(uint256(keccak256("cybro.storage.ERC4626Mixin")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC4626_MIXIN_STORAGE_LOCATION =
        0x6e11342261bfc2856d925166ae0cad24c6e018a9ba3525ef912dc39716e49200;

    uint32 public constant slippagePrecision = 10000;

    function __ERC4626Mixin_init() internal view onlyInitializing {
        if (address(feeProvider) != address(0)) {
            require(feeProvider.getPerformanceFee(address(0)) == 0, PerformanceFeeNotZero());
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Converts assets to shares.
    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        return assets * 10 ** decimals() / sharePrice();
    }

    /// @notice Converts shares to assets.
    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        return shares * sharePrice() / 10 ** decimals();
    }

    /// @notice Returns the maximum amount of assets that can be deposited.
    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    /// @notice Returns the maximum amount of shares that can be redeemed.
    function maxRedeem(address owner) public view virtual returns (uint256 maxShares) {
        return balanceOf(owner);
    }

    /**
     * @notice This function is used to preview the amount of shares that will be received when depositing assets.
     * Returns amount lower or equal to the actual amount of shares that will be received.
     * @param assets The amount of assets to deposit.
     * @return The amount of shares that will be received.
     */
    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(
            _applySlippageLoss(assets - (assets * feeProvider.getDepositFee(msg.sender)) / feePrecision)
        );
    }

    /**
     * @notice This function is used to preview the amount of assets that will be received when redeeming shares.
     * Returns amount lower or equal to the actual amount of assets that will be received.
     * @param shares The amount of shares to redeem.
     * @return The amount of assets that will be received.
     */
    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        uint256 assets = _applySlippageLoss(convertToAssets(shares));
        return assets - (assets * feeProvider.getWithdrawalFee(msg.sender)) / feePrecision;
    }

    /**
     * @notice This function is used to get the max slippage for preview functions.
     * For vaults that implement their own maxSlippage, this function returns the vault's maxSlippage value.
     * @return The max slippage for preview functions.
     */
    function getMaxSlippageForPreview() external view virtual returns (uint32) {
        ERC4626MixinStorage storage $ = _getERC4626MixinStorage();
        return $.maxSlippageForPreview;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice This function is used to set the max slippage for preview functions.
     * @param maxSlippageForPreview_ The max slippage for preview functions.
     */
    function setMaxSlippageForPreview(uint32 maxSlippageForPreview_) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        ERC4626MixinStorage storage $ = _getERC4626MixinStorage();
        $.maxSlippageForPreview = maxSlippageForPreview_;
    }

    /**
     * @notice This is a wrapper function that implements the IERC4626 deposit interface.
     * @param assets The amount of assets to deposit.
     * @param receiver The address of the receiver.
     * @return shares The amount of shares that will be received.
     */
    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        shares = deposit(assets, receiver, 0);
    }

    /**
     * @notice This is a wrapper function that implements the IERC4626 redeem interface.
     * @param shares The amount of shares to redeem.
     * @param receiver The address of the receiver.
     * @param owner The address of the owner.
     * @return assets The amount of assets that will be received.
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        assets = redeem(shares, receiver, owner, 0);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Overrides the BaseVault _update function to allow transfers.
    function _update(address from, address to, uint256 value) internal virtual override {
        ERC20Upgradeable._update(from, to, value);
    }

    /**
     * @notice Applies the slippage loss to the assets.
     * @param assets The amount of assets to apply the slippage loss to.
     * @return The amount of assets after the slippage loss.
     */
    function _applySlippageLoss(uint256 assets) internal view virtual returns (uint256) {
        ERC4626MixinStorage storage $ = _getERC4626MixinStorage();
        return assets - (assets * $.maxSlippageForPreview) / slippagePrecision;
    }
}
