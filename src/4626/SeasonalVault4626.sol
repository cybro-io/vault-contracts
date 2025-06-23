// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {ERC4626Mixin} from "../ERC4626Mixin.sol";
import {BaseVault} from "../BaseVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SeasonalVault} from "../SeasonalVault.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {IVault} from "../interfaces/IVault.sol";

contract SeasonalVault4626 is SeasonalVault, ERC4626Mixin {
    constructor(
        address payable _positionManager,
        IERC20Metadata _asset,
        address _token0,
        address _token1,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        IVault _token0Vault,
        IVault _token1Vault
    )
        SeasonalVault(_positionManager, _asset, _token0, _token1, _feeProvider, _feeRecipient, _token0Vault, _token1Vault)
    {}

    /// @inheritdoc SeasonalVault
    function initialize(address admin, string memory name, string memory symbol, address manager)
        public
        override
        initializer
    {
        __SeasonalVault_init(admin, name, symbol, manager);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function quoteWithdrawalFee(address account) public view override(BaseVault, ERC4626Mixin) returns (uint256) {
        // super.quoteWithdrawalFee will call ERC4626Mixin.quoteWithdrawalFee
        return super.quoteWithdrawalFee(account);
    }

    function getProfit(address account) public pure override(BaseVault, ERC4626Mixin) returns (uint256) {
        // super.getProfit will call ERC4626Mixin.getProfit
        return super.getProfit(account);
    }

    function getWaterline(address account) public pure override(BaseVault, ERC4626Mixin) returns (uint256) {
        // super.getWaterline will call ERC4626Mixin.getWaterline
        return super.getWaterline(account);
    }

    /// @notice This vault uses maxSlippage that is declared in SeasonalVault
    function getMaxSlippageForPreview() external view override returns (uint32) {
        return maxSlippage;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @inheritdoc ERC4626Mixin
    function deposit(uint256 assets, address receiver, uint256 minShares)
        public
        virtual
        override(BaseVault, ERC4626Mixin)
        whenNotPaused
        returns (uint256 shares)
    {
        // super.deposit will call ERC4626Mixin.deposit
        return super.deposit(assets, receiver, minShares);
    }

    function collectPerformanceFee(address[] memory accounts) public pure virtual override(BaseVault, ERC4626Mixin) {
        // super.collectPerformanceFee will call ERC4626Mixin.collectPerformanceFee
        super.collectPerformanceFee(accounts);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _update(address from, address to, uint256 value) internal override(BaseVault, ERC4626Mixin) {
        // super._update will call ERC4626Mixin._update
        super._update(from, to, value);
    }

    /// @notice This vault uses maxSlippage that is declared in SeasonalVault
    function _applySlippageLoss(uint256 assets) internal view override returns (uint256) {
        return assets - (assets * maxSlippage) / slippagePrecision;
    }

    function _applyPerformanceFee(uint256 assets, uint256, address)
        internal
        pure
        override(BaseVault, ERC4626Mixin)
        returns (uint256, uint256)
    {
        // super._applyPerformanceFee will call ERC4626Mixin._applyPerformanceFee
        return super._applyPerformanceFee(assets, 0, address(0));
    }

    /// @notice This vault uses maxSlippage that is declared in SeasonalVault
    function setMaxSlippageForPreview(uint32) external pure override {
        revert NotImplemented();
    }
}
