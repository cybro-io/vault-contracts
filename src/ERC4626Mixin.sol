// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {BaseVault} from "./BaseVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract ERC4626Mixin is BaseVault {
    using SafeERC20 for IERC20Metadata;

    error NotImplemented();

    uint32 public immutable slippagePrecision = 10000;

    uint32 public maxSlippage;

    function setMaxSlippage(uint32 maxSlippage_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxSlippage = maxSlippage_;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function convertToShares(uint256 assets) public view virtual returns (uint256 shares) {
        return assets * 10 ** decimals() / sharePrice();
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256 assets) {
        return shares * sharePrice() / 10 ** decimals();
    }

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxRedeem(address owner) public view virtual returns (uint256 maxShares) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(
            _applySlippageLoss(assets - (assets * feeProvider.getDepositFee(msg.sender)) / feePrecision)
        );
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        uint256 assets = _applySlippageLoss(convertToAssets(shares));
        return assets - (assets * feeProvider.getWithdrawalFee(msg.sender)) / feePrecision;
    }

    function quoteWithdrawalFee(address account) external view override returns (uint256) {
        if (address(feeProvider) == address(0)) {
            return 0;
        }
        uint256 assets = getBalanceInUnderlying(account);
        return assets * feeProvider.getWithdrawalFee(account) / feePrecision;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        shares = deposit(assets, receiver, 0);
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        assets = redeem(shares, receiver, owner, 0);
    }

    function deposit(uint256 assets, address receiver, uint256 minShares)
        public
        virtual
        override
        whenNotPaused
        returns (uint256 shares)
    {
        if (assets == 0) {
            return 0;
        }
        uint256 totalSupplyBefore = totalSupply();
        IERC20Metadata(asset()).safeTransferFrom(_msgSender(), address(this), assets);
        uint256 depositFee;
        (assets, depositFee) = address(feeProvider) == address(0) ? (assets, 0) : _applyDepositFee(assets);

        uint256 totalAssetsBefore = _deposit(assets);

        uint256 totalAssetsAfter = _totalAssetsPrecise();
        uint256 increase = totalAssetsAfter - totalAssetsBefore;

        shares = (totalAssetsBefore == 0 || totalSupplyBefore == 0)
            ? increase
            : totalSupplyBefore * increase / totalAssetsBefore;

        require(shares >= minShares, MinShares());

        _mint(receiver, shares);

        emit Deposit(_msgSender(), receiver, increase, shares, depositFee, totalSupplyBefore, totalAssetsBefore);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _update(address from, address to, uint256 value) internal override {
        // allow transfers
        super._update(from, to, value);
    }

    function _applyPerformanceFee(uint256 assets, uint256, address) internal pure override returns (uint256, uint256) {
        return (assets, 0);
    }

    function _applySlippageLoss(uint256 assets) internal view virtual returns (uint256) {
        return assets - (assets * maxSlippage) / slippagePrecision;
    }

    /* ========== NOT IMPLEMENTED FUNCTIONS ========== */

    function getWaterline(address) external pure override returns (uint256) {
        revert NotImplemented();
    }

    function getProfit(address) external pure override returns (uint256) {
        revert NotImplemented();
    }

    function collectPerformanceFee(address[] memory) external pure override {
        revert NotImplemented();
    }
}
