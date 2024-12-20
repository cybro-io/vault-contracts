// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {BaseVault} from "../BaseVault.sol";

/// @title BaseDexUniformVault
/// @notice This abstract contract provides a base implementation for managing liquidity on a decentralized exchange (DEX)
/// @dev This contract is meant to be inherited by specific implementations for different DEXes
abstract contract BaseDexUniformVault is BaseVault {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    bool public immutable isToken0;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /* ========== CONSTRUCTOR ========== */

    /// @notice Constructor that sets the initial token addresses and their respective decimals
    /// @param _token0 The address of token0
    /// @param _token1 The address of token1
    /// @param _asset The base token of the vault
    /// @param _feeProvider The fee provider contract
    /// @param _feeRecipient The address that receives the fees
    constructor(
        address _token0,
        address _token1,
        IERC20Metadata _asset,
        IFeeProvider _feeProvider,
        address _feeRecipient
    ) BaseVault(_asset, _feeProvider, _feeRecipient) {
        (token0, token1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);
        isToken0 = token0 == address(_asset);
        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();
    }

    /* ========== INITIALIZER ========== */

    /// @notice Initializes the contract with the given admin address
    /// @dev This function should be called once during deployment to set up the ownership
    /// @param admin The address of the admin
    /// @param manager The address of the manager
    function __BaseDexUniformVault_init(address admin, address manager) public onlyInitializing {
        __BaseVault_init(admin, manager);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @notice Deposits liquidity into the vault by swapping and adding tokens to the DEX
    /// @return shares The number of shares minted for the deposited liquidity
    function deposit(uint256 assets, address receiver, uint256 minShares)
        public
        virtual
        override
        whenNotPaused
        returns (uint256 shares)
    {
        IERC20Metadata(asset()).safeTransferFrom(msg.sender, address(this), assets);
        uint256 depositFee;
        (assets, depositFee) = address(feeProvider) == address(0) ? (assets, 0) : _applyDepositFee(assets);

        (uint256 amount0, uint256 amount1) = _getAmounts(assets);

        if (isToken0) {
            amount0 = amount0;
            amount1 = _swap(true, amount1);
        } else {
            amount0 = _swap(false, amount0);
            amount1 = amount1;
        }

        uint256 totalSupplyBefore = totalSupply();
        uint256 tvlBefore = totalSupplyBefore == 0 ? 0 : totalAssets();

        (uint256 amount0Used, uint256 amount1Used, uint256 liquidityReceived) = _addLiquidity(amount0, amount1);

        // Calculate remaining amounts after liquidity provision
        amount0 -= amount0Used;
        amount1 -= amount1Used;

        uint256 deposited = _calculateInBaseToken(amount0Used, amount1Used);
        shares = totalSupplyBefore == 0 ? deposited : totalSupplyBefore * deposited / tvlBefore;

        require(shares >= minShares, "minShares");

        _waterline[receiver] += deposited;

        _mint(receiver, shares);

        // Handle remaining tokens and return them to the user if necessary
        if (amount0 > 0 && !isToken0) {
            amount1 += _swap(true, amount0);
            IERC20Metadata(token1).safeTransfer(msg.sender, amount1);
        } else if (amount1 > 0 && isToken0) {
            amount0 += _swap(false, amount1);
            IERC20Metadata(token0).safeTransfer(msg.sender, amount0);
        } else {
            if (isToken0 && amount0 > 0) {
                IERC20Metadata(token0).safeTransfer(msg.sender, amount0);
            } else if (amount1 > 0) {
                IERC20Metadata(token1).safeTransfer(msg.sender, amount1);
            }
        }

        emit Deposit(_msgSender(), receiver, liquidityReceived, shares, depositFee, totalSupplyBefore, tvlBefore);
    }

    /// @notice Redeems liquidity from the vault by burning shares and withdrawing tokens from the DEX
    /// @dev The function handles swaps between token0 and token1 to ensure proper asset distribution
    /// @param shares The number of shares to redeem
    /// @param receiver The address that will receive the withdrawn tokens
    /// @param owner The address of the owner of the shares being redeemed
    /// @param minAssets The minimum amount of the output token required for the transaction to succeed
    /// @return assets The amount of the output token received
    function redeem(uint256 shares, address receiver, address owner, uint256 minAssets)
        public
        virtual
        override
        returns (uint256 assets)
    {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        uint256 tvlBefore = totalAssets();
        uint256 totalSupplyBefore = totalSupply();

        uint256 liquidityToRemove = shares * _getTokenLiquidity() / totalSupplyBefore;
        (uint256 amount0, uint256 amount1) = _removeLiquidity(liquidityToRemove);

        // Calculate the assets to return based on the desired output token
        if (isToken0) {
            assets = amount0 + _swap(false, amount1);
        } else {
            assets = amount1 + _swap(true, amount0);
        }

        // Ensure that the amount received is above the minimum threshold
        require(assets >= minAssets, "slippage");
        uint256 withdrawalFee;
        if (address(feeProvider) != address(0)) {
            (assets,) = _applyPerformanceFee(assets, shares, owner);
            (assets, withdrawalFee) = _applyWithdrawalFee(assets, owner);
        }

        _burn(owner, shares);

        IERC20Metadata(asset()).safeTransfer(receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, shares, withdrawalFee, totalSupplyBefore, tvlBefore);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Retrieves the amounts of token0 and token1 that correspond to the current liquidity
    /// @dev Must be implemented by the inheriting contract to provide specific logic for the DEX
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function getPositionAmounts() public view virtual returns (uint256 amount0, uint256 amount1);

    /// @notice Abstract function to retrieve the current square root price of the Dex pool
    /// @dev Must be implemented by the inheriting contract
    /// @return The current square root price
    function getCurrentSqrtPrice() public view virtual returns (uint160);

    /// @inheritdoc BaseVault
    function totalAssets() public view virtual override returns (uint256 totalValue) {
        (uint256 total0, uint256 total1) = getPositionAmounts();
        totalValue = _calculateInBaseToken(total0, total1);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Retrieves the current liquidity of the Dex position
    /// @return liquidity The current liquidity of the position
    function _getTokenLiquidity() internal view virtual returns (uint256 liquidity);

    /// @dev Internal function to perform a token swap on the DEX
    /// @param zeroForOne Whether to swap token0 for token1 (true) or token1 for token0 (false)
    /// @param amount The amount of tokens to swap
    /// @return The amount of tokens received from the swap
    function _swap(bool zeroForOne, uint256 amount) internal virtual returns (uint256);

    /// @dev Internal function to add liquidity to the DEX
    /// @param amount0 The amount of token0 to add
    /// @param amount1 The amount of token1 to add
    /// @return amount0Used The amount of token0 actually used in the liquidity addition
    /// @return amount1Used The amount of token1 actually used in the liquidity addition
    function _addLiquidity(uint256 amount0, uint256 amount1)
        internal
        virtual
        returns (uint256 amount0Used, uint256 amount1Used, uint256 liquidity);

    /// @dev Internal function to remove liquidity from the DEX
    /// @param liquidity The amount of liquidity to remove
    /// @return The amounts of token0 and token1 withdrawn
    function _removeLiquidity(uint256 liquidity) internal virtual returns (uint256, uint256);

    /// @notice Calculates the amounts neeeded to get swapped into token0 and token1 to place a position in the given range.
    /// @param amount The total assets to be divided between token0 and token1
    /// @return amountFor0 The amount of token0 to be added
    /// @return amountFor1 The amount of token1 to be added
    function _getAmounts(uint256 amount) internal view virtual returns (uint256 amountFor0, uint256 amountFor1);

    /// @notice Calculates the amount of tokens in base token
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    /// @return The amount of tokens in base token
    function _calculateInBaseToken(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        uint256 sqrtPrice = uint256(getCurrentSqrtPrice());
        return isToken0
            ? Math.mulDiv(amount1, 2 ** 192, sqrtPrice * sqrtPrice) + amount0
            : Math.mulDiv(amount0, sqrtPrice * sqrtPrice, 2 ** 192) + amount1;
    }

    function _deposit(uint256) internal virtual override {
        revert("BaseDexUniformVault: deposit not implemented");
    }

    function _redeem(uint256) internal virtual override returns (uint256) {
        revert("BaseDexUniformVault: redeem not implemented");
    }
}