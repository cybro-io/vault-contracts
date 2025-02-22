// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVault} from "../BaseVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {IPSM3} from "../interfaces/spark/IPSM3.sol";
import {ISSRAuthOracle} from "../interfaces/spark/ISSRAuthOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SparkVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    IPSM3 public immutable psm;
    IERC20Metadata public immutable susds;
    ISSRAuthOracle public immutable rateProvider;
    uint8 public immutable susdsDecimals;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, IPSM3 _psm, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVault(_asset, _feeProvider, _feeRecipient)
    {
        psm = _psm;
        rateProvider = ISSRAuthOracle(_psm.rateProvider());
        susds = IERC20Metadata(_psm.susds());
        susdsDecimals = susds.decimals();

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        IERC20Metadata(asset()).forceApprove(address(psm), type(uint256).max);
        susds.forceApprove(address(psm), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    /// @inheritdoc BaseVault
    function totalAssets() public view override returns (uint256) {
        return psm.previewSwapExactIn(address(susds), address(asset()), susds.balanceOf(address(this)));
    }

    /// @inheritdoc BaseVault
    function underlyingTVL() external view virtual override returns (uint256) {
        return psm.totalAssets();
    }

    /// @inheritdoc BaseVault
    function _deposit(uint256 assets) internal override {
        psm.swapExactIn(asset(), address(susds), assets, 0, address(this), 0);
    }

    /// @inheritdoc BaseVault
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        assets = psm.swapExactIn(
            address(susds), asset(), shares * susds.balanceOf(address(this)) / totalSupply(), 0, address(this), 0
        );
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(susds);
    }
}
