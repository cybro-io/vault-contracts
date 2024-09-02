// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IDexVault} from "./interfaces/IDexVault.sol";

/// @title BaseDexUniformVault
/// @notice This abstract contract provides a base implementation for managing liquidity on a decentralized exchange (DEX)
/// @dev This contract is meant to be inherited by specific implementations for different DEXes
abstract contract BaseDexUniformVault is ERC20Upgradeable, OwnableUpgradeable, IDexVault {
    using SafeERC20 for IERC20Metadata;

    /// @dev Custom error that is thrown when attempting to withdraw an invalid token.
    error InvalidTokenToWithdraw(address token);

    /* ========== IMMUTABLE VARIABLES ========== */

    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice Emitted when liquidity is deposited into the vault
    /// @param sender The address initiating the deposit
    /// @param owner The address that receives the vault tokens
    /// @param liquidity The amount of liquidity added
    /// @param shares The number of shares minted to the owner
    event Deposit(address indexed sender, address indexed owner, uint256 liquidity, uint256 shares);

    /// @notice Emitted when liquidity is withdrawn from the vault
    /// @param sender The address initiating the withdrawal
    /// @param receiver The address receiving the withdrawn tokens
    /// @param owner The address of the owner of the shares being redeemed
    /// @param shares The number of shares burned from the owner
    event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 shares);

    /// @notice Constructor that sets the initial token addresses and their respective decimals
    /// @param _token0 The address of token0
    /// @param _token1 The address of token1
    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();
    }

    /// @notice Initializes the contract with the given admin address
    /// @dev This function should be called once during deployment to set up the ownership
    /// @param admin The address of the admin
    function __BaseDexUniformVault_init(address admin) public onlyInitializing {
        __Ownable_init(admin);
    }

    /// @notice Retrieves the current liquidity of the Dex position
    /// @return liquidity The current liquidity of the position
    function _getTokenLiquidity() internal view virtual returns (uint256 liquidity);

    /// @notice Abstract function to retrieve the current square root price of the Dex pool
    /// @dev Must be implemented by the inheriting contract
    /// @return The current square root price
    function getCurrentSqrtPrice() public view virtual override returns (uint160);

    /// @notice Retrieves the amounts of token0 and token1 that correspond to the current liquidity
    /// @dev Must be implemented by the inheriting contract to provide specific logic for the DEX
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function getPositionAmounts() public view virtual returns (uint256 amount0, uint256 amount1);

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

    /// @notice Deposits liquidity into the vault by swapping and adding tokens to the DEX
    /// @dev The function handles swaps between token0 and token1 to ensure proper liquidity ratios
    /// @param inToken0 Indicates whether the input token is token0 (true) or token1 (false)
    /// @param amount The amount of the input token to deposit
    /// @param receiver The address that will receive the vault shares
    /// @param minSqrtPriceX96 The minimum price threshold for the swap
    /// @param maxSqrtPriceX96 The maximum price threshold for the swap
    /// @return shares The number of shares minted for the deposited liquidity
    function deposit(bool inToken0, uint256 amount, address receiver, uint160 minSqrtPriceX96, uint160 maxSqrtPriceX96)
        public
        returns (uint256 shares)
    {
        if (inToken0) {
            IERC20Metadata(token0).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            IERC20Metadata(token1).safeTransferFrom(msg.sender, address(this), amount);
        }

        uint256 totalLiquidityBefore = _getTokenLiquidity();

        uint256 amount0;
        uint256 amount1;
        if (inToken0) {
            require(getCurrentSqrtPrice() <= maxSqrtPriceX96, "sqrt price is too high");
            amount0 = amount / 2;
            amount1 = _swap(true, amount - amount0);
            require(getCurrentSqrtPrice() >= minSqrtPriceX96, "sqrt price is too low");
        } else {
            require(getCurrentSqrtPrice() >= minSqrtPriceX96, "sqrt price is too low");
            amount1 = amount / 2;
            amount0 = _swap(false, amount - amount1);
            require(getCurrentSqrtPrice() <= maxSqrtPriceX96, "sqrt price is too high");
        }

        (uint256 amount0Used, uint256 amount1Used, uint256 liquidityReceived) = _addLiquidity(amount0, amount1);

        // Calculate remaining amounts after liquidity provision
        amount0 -= amount0Used;
        amount1 -= amount1Used;

        // Calculate the shares to mint based on the liquidity increase
        shares =
            totalLiquidityBefore == 0 ? liquidityReceived : totalSupply() * liquidityReceived / totalLiquidityBefore;

        _mint(receiver, shares);

        // Handle remaining tokens and return them to the user if necessary
        if (amount0 > 0 && !inToken0) {
            amount1 += _swap(true, amount0);
            IERC20Metadata(token1).safeTransfer(msg.sender, amount1);
        } else if (amount1 > 0 && inToken0) {
            amount0 += _swap(false, amount1);
            IERC20Metadata(token0).safeTransfer(msg.sender, amount0);
        } else {
            if (inToken0 && amount0 > 0) {
                IERC20Metadata(token0).safeTransfer(msg.sender, amount0);
            } else if (amount1 > 0) {
                IERC20Metadata(token1).safeTransfer(msg.sender, amount1);
            }
        }

        emit Deposit(_msgSender(), receiver, liquidityReceived, shares);
    }

    /// @notice Redeems liquidity from the vault by burning shares and withdrawing tokens from the DEX
    /// @dev The function handles swaps between token0 and token1 to ensure proper asset distribution
    /// @param inToken0 Indicates whether the output token should be token0 (true) or token1 (false)
    /// @param shares The number of shares to redeem
    /// @param receiver The address that will receive the withdrawn tokens
    /// @param owner The address of the owner of the shares being redeemed
    /// @param minAmountOut The minimum amount of the output token required for the transaction to succeed
    /// @return assets The amount of the output token received
    function redeem(bool inToken0, uint256 shares, address receiver, address owner, uint256 minAmountOut)
        public
        virtual
        returns (uint256 assets)
    {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        (uint256 amount0, uint256 amount1) = _removeLiquidity(shares);

        _burn(owner, shares);

        // Calculate the assets to return based on the desired output token
        if (inToken0) {
            assets = amount0 + _swap(false, amount1);
        } else {
            assets = amount1 + _swap(true, amount0);
        }

        // Ensure that the amount received is above the minimum threshold
        require(assets >= minAmountOut, "slippage");

        if (inToken0) {
            IERC20Metadata(token0).safeTransfer(receiver, assets);
        } else {
            IERC20Metadata(token1).safeTransfer(receiver, assets);
        }

        emit Withdraw(_msgSender(), receiver, owner, shares);
    }

    /// @dev Internal function to validate whether a token can be recovered by the owner
    /// @param token The address of the token to validate
    /// @return A boolean indicating whether the token can be recovered
    function _validateTokenToRecover(address token) internal virtual returns (bool);

    /// @notice Allows the owner to withdraw funds accidentally sent to the contract
    /// @dev This function can only be called by the owner of the contract
    /// @param token The address of the token to withdraw, or address(0) for ETH
    function withdrawFunds(address token) external virtual onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "failed to send ETH");
        } else if (_validateTokenToRecover(token)) {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        } else {
            revert InvalidTokenToWithdraw(token);
        }
    }
}
