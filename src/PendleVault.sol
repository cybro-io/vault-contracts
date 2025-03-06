// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {BaseVault, IERC20Metadata} from "./BaseVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPActionAddRemoveLiqV3} from "@pendle/core-v2/interfaces/IPActionAddRemoveLiqV3.sol";
import {IPAllActionV3} from "@pendle/core-v2/interfaces/IPAllActionV3.sol";
import {IPMarket} from "@pendle/core-v2/interfaces/IPMarket.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {IPPYLpOracle} from "@pendle/core-v2/interfaces/IPPYLpOracle.sol";
import "@pendle/core-v2/interfaces/IPAllActionTypeV3.sol";
import {console} from "forge-std/console.sol";

contract PendleVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    uint32 public constant TWAP_DURATION = 1200;

    /* ========== IMMUTABLE VARIABLES ========== */

    IPAllActionV3 public immutable router;
    IPPYLpOracle public immutable oracle;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    IPMarket public market;

    constructor(
        IERC20Metadata _asset,
        address _router,
        IPPYLpOracle _oracle,
        IFeeProvider _feeProvider,
        address _feeRecipient
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        router = IPAllActionV3(_router);
        oracle = _oracle;

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol, address manager, address market_)
        public
        initializer
    {
        IERC20Metadata(asset()).forceApprove(address(router), type(uint256).max);
        IERC20Metadata(market_).forceApprove(address(router), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
        market = IPMarket(market_);
    }

    function setNewMarket(address _market) external onlyRole(MANAGER_ROLE) {
        market = IPMarket(_market);
    }

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        return market.balanceOf(address(this)) * oracle.getLpToAssetRate(address(market), TWAP_DURATION)
            / (10 ** market.decimals());
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view virtual override returns (uint256) {
        return
            market.totalSupply() * oracle.getLpToAssetRate(address(market), TWAP_DURATION) / (10 ** market.decimals());
    }

    function _deposit(uint256 assets) internal override {
        router.addLiquiditySingleToken(
            address(this),
            address(market),
            0,
            createDefaultApproxParams(),
            createTokenInputSimple(asset(), assets),
            createEmptyLimitOrderData()
        );
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = shares * market.balanceOf(address(this)) / totalSupply();
        (assets,,) = router.removeLiquiditySingleToken(
            address(this), address(market), assets, createTokenOutputSimple(asset(), 0), createEmptyLimitOrderData()
        );
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(market);
    }
}
