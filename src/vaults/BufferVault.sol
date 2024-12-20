// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {BaseVault} from "../BaseVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract BufferVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    constructor(IERC20Metadata _asset, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVault(_asset, _feeProvider, _feeRecipient)
    {
        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol, address manager)
        public
        virtual
        initializer
    {
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        return IERC20Metadata(asset()).balanceOf(address(this));
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view virtual override returns (uint256) {
        return totalAssets();
    }

    function _deposit(uint256 assets) internal pure override {}

    function _redeem(uint256 shares) internal view override returns (uint256 assets) {
        assets = shares * totalAssets() / totalSupply();
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address) internal pure override returns (bool) {
        return true;
    }
}
