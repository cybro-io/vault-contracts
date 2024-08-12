// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

/// @title BaseDexVault
/// @notice This abstract contract provides a base implementation for managing liquidity on a decentralized exchange (Dex)
/// @dev This contract is meant to be inherited by specific implementations for different DEXes
abstract contract BaseDexVault is ERC20Upgradeable, OwnableUpgradeable, IERC721Receiver {
    using SafeERC20 for IERC20Metadata;

    /// @notice Address of token0 used in the liquidity pool
    address public immutable token0;

    /// @notice Address of token1 used in the liquidity pool
    address public immutable token1;

    /// @notice The ID of the NFT representing the Dex liquidity position
    uint256 public positionTokenId;

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

    /// @param _token0 The address of token0
    /// @param _token1 The address of token1
    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    /// @notice Initializes the contract with the given admin address
    /// @param admin The address of the admin
    function __BaseDexVault_init(address admin) public onlyInitializing {
        __Ownable_init(admin);
    }

    /// @notice Calculates the amounts of token0 and token1 needed based on the specified price range
    /// @param sqrtPriceAX96 The square root of the price at the lower bound of the range
    /// @param sqrtPriceX96 The current square root price
    /// @param sqrtPriceBX96 The square root of the price at the upper bound of the range
    /// @param assets The total assets to be divided between token0 and token1
    /// @return amountFor0 The amount of token0 required
    /// @return amountFor1 The amount of token1 required
    function getAmounts(uint160 sqrtPriceAX96, uint160 sqrtPriceX96, uint160 sqrtPriceBX96, uint256 assets)
        internal
        pure
        returns (uint256 amountFor0, uint256 amountFor1)
    {
        if (sqrtPriceX96 <= sqrtPriceAX96) {
            amountFor0 = assets;
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            uint256 n = FullMath.mulDiv(sqrtPriceBX96, sqrtPriceX96 - sqrtPriceAX96, FixedPoint96.Q96);
            uint256 d = FullMath.mulDiv(sqrtPriceX96, sqrtPriceBX96 - sqrtPriceX96, FixedPoint96.Q96);
            uint256 x = FullMath.mulDiv(n, FixedPoint96.Q96, d);
            amountFor0 = FullMath.mulDiv(assets, FixedPoint96.Q96, x + FixedPoint96.Q96);
            amountFor1 = assets - amountFor0;
        } else {
            amountFor1 = assets;
        }
    }

    /// @notice Abstract function to perform a token swap
    /// @dev Must be implemented by the inheriting contract
    /// @param zeroForOne A boolean indicating the direction of the swap (true for token0 to token1, false for token1 to token0)
    /// @param amount The amount of the input token to be swapped
    /// @return The amount of the output token received from the swap
    function _swap(bool zeroForOne, uint256 amount) internal virtual returns (uint256);

    /// @notice Abstract function to mint a new Dex liquidity position
    /// @dev Must be implemented by the inheriting contract
    /// @param amount0 The amount of token0 to add to the liquidity position
    /// @param amount1 The amount of token1 to add to the liquidity position
    /// @param tickLower The lower tick of the liquidity position
    /// @param tickUpper The upper tick of the liquidity position
    /// @return tokenId The ID of the newly minted liquidity position
    /// @return liquidity The amount of liquidity added
    /// @return amount0Used The amount of token0 used in the liquidity provision
    /// @return amount1Used The amount of token1 used in the liquidity provision
    function _mintPosition(uint256 amount0, uint256 amount1, int24 tickLower, int24 tickUpper)
        internal
        virtual
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0Used, uint256 amount1Used);

    /// @notice Abstract function to increase the liquidity of an existing Dex position
    /// @dev Must be implemented by the inheriting contract
    /// @param amount0 The amount of token0 to add to the liquidity position
    /// @param amount1 The amount of token1 to add to the liquidity position
    /// @return liquidity The amount of liquidity added to the position
    /// @return amount0Used The amount of token0 used in the liquidity provision
    /// @return amount1Used The amount of token1 used in the liquidity provision
    function _increaseLiquidity(uint256 amount0, uint256 amount1)
        internal
        virtual
        returns (uint128 liquidity, uint256 amount0Used, uint256 amount1Used);

    /// @notice Abstract function to decrease the liquidity of an existing Dex position
    /// @dev Must be implemented by the inheriting contract
    /// @param liquidity The amount of liquidity to remove from the position
    /// @return amount0 The amount of token0 received from decreasing liquidity
    /// @return amount1 The amount of token1 received from decreasing liquidity
    function _decreaseLiquidity(uint128 liquidity) internal virtual returns (uint256 amount0, uint256 amount1);

    /// @notice Abstract function to collect fees earned by the Dex position
    /// @dev Must be implemented by the inheriting contract
    /// @param amountMax0 The maximum amount of token0 to collect
    /// @param amountMax1 The maximum amount of token1 to collect
    /// @return amount0 The amount of token0 collected
    /// @return amount1 The amount of token1 collected
    function _collect(uint128 amountMax0, uint128 amountMax1)
        internal
        virtual
        returns (uint256 amount0, uint256 amount1);

    /// @notice Retrieves the current liquidity of the Dex position
    /// @return liquidity The current liquidity of the position
    function _getTokenLiquidity() internal view virtual returns (uint128 liquidity);

    /// @notice Retrieves the amount of tokens owed to the vault from the Dex position
    /// @return amount0 The amount of token0 owed
    /// @return amount1 The amount of token1 owed
    function _getTokensOwed() internal virtual returns (uint128 amount0, uint128 amount1);

    /// @notice Abstract function to retrieve the current square root price of the Dex pool
    /// @dev Must be implemented by the inheriting contract
    /// @return The current square root price
    function _getCurrentSqrtPrice() internal view virtual returns (uint160);

    /// @notice Abstract function to retrieve the current ticks of the Dex pool
    /// @dev Must be implemented by the inheriting contract
    /// @return The current ticks of the pool
    function _getTicks() internal view virtual returns (int24, int24);

    /// @notice Deposits tokens into the vault and provides liquidity on Dex
    /// @param inToken0 A boolean indicating whether the deposit is in token0 (true) or token1 (false)
    /// @param amount The amount of the token being deposited
    /// @param receiver The address that will receive the minted shares
    /// @return shares The number of shares minted to the receiver
    function deposit(bool inToken0, uint256 amount, address receiver) public returns (uint256 shares) {
        if (inToken0) {
            IERC20Metadata(token0).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            IERC20Metadata(token1).safeTransferFrom(msg.sender, address(this), amount);
        }
        uint160 sqrtPriceLower = TickMath.MIN_SQRT_RATIO;
        uint160 sqrtPriceUpper = TickMath.MAX_SQRT_RATIO;

        (uint256 amountFor0, uint256 amountFor1) =
            getAmounts(sqrtPriceLower, _getCurrentSqrtPrice(), sqrtPriceUpper, amount);
        uint256 amount0;
        uint256 amount1;
        if (inToken0) {
            amount0 = amountFor0;
            amount1 = _swap(true, amountFor1);
        } else {
            amount0 = _swap(false, amountFor0);
            amount1 = amountFor1;
        }

        uint128 liquidityBefore = positionTokenId == 0 ? 0 : _getTokenLiquidity();
        uint128 liquidityReceived;
        uint256 amount0Used;
        uint256 amount1Used;
        if (positionTokenId == 0) {
            (int24 tickLower, int24 tickUpper) = _getTicks();
            (positionTokenId, liquidityReceived, amount0Used, amount1Used) =
                _mintPosition(amount0, amount1, tickLower, tickUpper);
        } else {
            (liquidityReceived, amount0Used, amount1Used) = _increaseLiquidity(amount0, amount1);
        }
        // Calculate remaining amounts after liquidity provision
        amount0 -= amount0Used;
        amount1 -= amount1Used;

        shares = liquidityBefore == 0 ? liquidityReceived : totalSupply() * liquidityReceived / liquidityBefore;
        _mint(receiver, shares);

        // Return remaining tokens to the user
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

    /// @notice Redeems shares from the vault by withdrawing liquidity from Dex
    /// @param inToken0 A boolean indicating whether the redemption is in token0 (true) or token1 (false)
    /// @param shares The number of shares to redeem
    /// @param receiver The address receiving the withdrawn tokens
    /// @param owner The address of the owner of the shares being redeemed
    /// @return amount0 The amount of token0 sent to the user
    /// @return amount1 The amount of token1 sent to the user
    function redeem(bool inToken0, uint256 shares, address receiver, address owner)
        public
        returns (uint256 amount0, uint256 amount1)
    {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), shares);
        }

        uint128 liquidityToRemove = uint128(shares * _getTokenLiquidity() / totalSupply());
        (uint128 owed0, uint128 owed1) = _getTokensOwed();
        (amount0, amount1) = _decreaseLiquidity(liquidityToRemove);
        (amount0, amount1) = _collect(
            uint128(shares * owed0 / totalSupply() + amount0), uint128(shares * owed1 / totalSupply() + amount1)
        );

        _burn(owner, shares);

        if (inToken0) {
            amount0 += _swap(false, amount1);
            amount1 = 0;
            IERC20Metadata(token0).safeTransfer(receiver, amount0);
        } else {
            amount1 += _swap(true, amount0);
            amount0 = 0;
            IERC20Metadata(token1).safeTransfer(receiver, amount1);
        }

        emit Withdraw(_msgSender(), receiver, owner, shares);
    }

    /// @notice It is function only used to withdraw funds accidentally sent to the contract.
    /// @param token The address of the token to withdraw (use address(0) for ETH)
    function withdrawFunds(address token) external virtual onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "failed to send ETH");
        } else {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
