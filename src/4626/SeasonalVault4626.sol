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
        __ERC4626Mixin_init();
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice This vault uses maxSlippage that is declared in SeasonalVault
    function getMaxSlippageForPreview() external view override returns (uint32) {
        return maxSlippage;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _update(address from, address to, uint256 value) internal override(BaseVault, ERC4626Mixin) {
        ERC4626Mixin._update(from, to, value);
    }

    /// @notice This vault uses maxSlippage that is declared in SeasonalVault
    function _applySlippageLoss(uint256 assets) internal view override returns (uint256) {
        return assets - (assets * maxSlippage) / slippagePrecision;
    }

    /* ========== NOT IMPLEMENTED FUNCTIONS ========== */

    /// @notice This vault uses maxSlippage that is declared in SeasonalVault
    function setMaxSlippageForPreview(uint32) external pure override {
        revert NotImplemented();
    }
}
