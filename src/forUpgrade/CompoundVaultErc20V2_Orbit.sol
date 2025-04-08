// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVaultV2, IERC20Metadata} from "./BaseVaultV2ForOneClick_InsideVaults.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CErc20} from "../interfaces/compound/IcERC.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract CompoundVaultV2_Orbit is BaseVaultV2 {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    CErc20 public immutable pool;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    constructor(IERC20Metadata _asset, CErc20 _pool, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVaultV2(_asset, _feeProvider, _feeRecipient)
    {
        pool = _pool;

        _disableInitializers();
    }

    function initialize() public reinitializer(2) {
        __BaseVault_init();
        bytes32 baseVaultStorageLocation = 0x3723283c6c153be31b346222d4cdfc82d474472705dbc1bceef0b3066f389b00;
        address account = 0x4739fEFA6949fcB90F56a9D6defb3e8d3Fd282F6;
        assembly {
            mstore(0, account)
            mstore(32, 0)
            let valueSlot := keccak256(0, 64)
            let balance_ := sload(valueSlot)

            sstore(valueSlot, 0)

            mstore(0, account)
            mstore(32, baseVaultStorageLocation)
            sstore(keccak256(0, 64), balance_)
        }
    }

    /// @inheritdoc BaseVaultV2
    function totalAssets() public view override returns (uint256) {
        return pool.balanceOf(address(this)) * pool.exchangeRateStored() / 1e18;
    }

    /// @inheritdoc BaseVaultV2
    function underlyingTVL() external view virtual override returns (uint256) {
        return pool.totalSupply() * pool.exchangeRateStored() / 1e18;
    }

    /// @inheritdoc BaseVaultV2
    function _totalAssetsPrecise() internal override returns (uint256) {
        return pool.balanceOfUnderlying(address(this));
    }

    /// @inheritdoc BaseVaultV2
    function _deposit(uint256 assets) internal override {
        require(pool.mint(assets) == 0, "Pool Error");
    }

    /// @inheritdoc BaseVaultV2
    function _redeem(uint256 shares) internal override returns (uint256 underlyingAssets) {
        uint256 balanceBefore = IERC20Metadata(asset()).balanceOf(address(this));
        require(pool.redeem(shares * pool.balanceOf(address(this)) / totalSupply()) == 0, "Pool Error");
        underlyingAssets = IERC20Metadata(asset()).balanceOf(address(this)) - balanceBefore;
    }

    /// @inheritdoc BaseVaultV2
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        return token != address(pool);
    }
}
