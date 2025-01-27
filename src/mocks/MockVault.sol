// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {BaseVault, IERC20Metadata, ERC20Upgradeable} from "../BaseVault.sol";
import {ERC20Mock} from "./ERC20Mock.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract MockVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    uint256 liquidityTokenBalance;
    uint256 lastTimestamp;

    constructor(IERC20Metadata _asset, IFeeProvider _feeProvider, address _feeRecipient)
        BaseVault(_asset, _feeProvider, _feeRecipient)
    {
        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol, address manager) public initializer {
        __ERC20_init(name, symbol);
        __BaseVault_init(admin, manager);
    }

    function totalAssets() public view override returns (uint256) {
        return liquidityTokenBalance;
    }

    function underlyingTVL() external view virtual override returns (uint256) {
        return liquidityTokenBalance;
    }

    modifier _balanceIncrease() {
        uint256 increaseAmount = liquidityTokenBalance / 365 days * (block.timestamp - lastTimestamp);
        liquidityTokenBalance += increaseAmount;
        lastTimestamp = block.timestamp;
        ERC20Mock(super.asset()).mint(address(this), increaseAmount);
        _;
    }

    function _deposit(uint256 assets) internal override _balanceIncrease {
        liquidityTokenBalance += assets;
    }

    function _redeem(uint256 shares) internal override _balanceIncrease returns (uint256 assets) {
        assets = shares * liquidityTokenBalance / totalSupply();
        liquidityTokenBalance -= assets;
    }

    function _validateTokenToRecover(address) internal virtual override returns (bool) {
        return true;
    }
}
