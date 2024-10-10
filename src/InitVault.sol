// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.26;

import {BaseVault, IERC20Metadata, ERC20Upgradeable} from "./BaseVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IInitCore} from "./interfaces/init/IInitCore.sol";
import {IERC20RebasingWrapper} from "./interfaces/init/IERC20RebasingWrapper.sol";
import {IInitLendingPool} from "./interfaces/init/IInitLendingPool.sol";

/// @title InitVault
/// @notice A vault contract for interacting with Init Capital protocol
/// @dev Inherits from BaseVault and implements Init-specific logic
contract InitVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    /// @notice The Init core contract
    IInitCore public immutable core;
    /// @notice The Init pool token
    IERC20Metadata public immutable pool;
    /// @notice The underlying token of the Init pool
    IERC20Metadata public immutable underlying;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice Constructor to set up immutable variables
    /// @param _pool The Init pool address
    constructor(IERC20Metadata _pool)
        BaseVault(
            IERC20Metadata(IERC20RebasingWrapper(IInitLendingPool(address(_pool)).underlyingToken()).underlyingToken())
        )
    {
        pool = _pool;
        core = IInitCore(IInitLendingPool(address(pool)).core());
        underlying = IERC20Metadata(IInitLendingPool(address(pool)).underlyingToken());

        _disableInitializers();
    }

    function initialize(address admin, string memory name, string memory symbol) public initializer {
        if (asset() != address(underlying)) {
            IERC20Metadata(asset()).forceApprove(address(underlying), type(uint256).max);
        }
        __ERC20_init(name, symbol);
        __BaseVault_init(admin);
    }

    /// @notice Returns the total assets in the vault
    /// @return The total balance of pool tokens held by the vault
    function totalAssets() public view override returns (uint256) {
        return IInitLendingPool(address(underlying)).toAmt(
            IInitLendingPool(address(pool)).toAmt(pool.balanceOf(address(this)))
        );
    }

    /// @notice Internal function to handle deposits
    /// @param assets The amount of assets to deposit
    function _deposit(uint256 assets) internal override {
        // Convert asset amount to underlying token amount
        uint256 assetsUnderlying = IERC20RebasingWrapper(address(underlying)).wrap(assets);
        // Transfer underlying tokens to the pool
        underlying.safeTransfer(address(pool), assetsUnderlying);
        // Mint pool tokens to this vault
        core.mintTo(address(pool), address(this));
    }

    /// @notice Internal function to handle redemptions
    /// @param shares The amount of shares to redeem
    /// @return assets The amount of assets redeemed
    function _redeem(uint256 shares) internal override returns (uint256 assets) {
        // Calculate the amount of pool tokens to burn based on shares
        uint256 assetsToBurn = shares * pool.balanceOf(address(this)) / totalSupply();
        // Transfer pool tokens to be burned
        pool.safeTransfer(address(pool), assetsToBurn);
        // Burn pool tokens and receive underlying tokens
        uint256 assetsReceived = core.burnTo(address(pool), address(this));
        assets = IERC20RebasingWrapper(address(underlying)).unwrap(assetsReceived);
    }

    /// @notice Validates if a token can be recovered from the vault
    /// @param token The address of the token to recover
    /// @return bool Returns true if the token can be recovered, false otherwise
    function _validateTokenToRecover(address token) internal virtual override returns (bool) {
        // Prevent recovery of the pool token
        return token != address(pool);
    }
}
