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
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {IDexVault} from "./interfaces/IDexVault.sol";
import {BaseDexUniformVault} from "./BaseDexUniformVault.sol";

/// @title BaseDexVault
/// @notice This abstract contract provides a base implementation for managing liquidity on a decentralized exchange (Dex)
/// @dev This contract is meant to be inherited by specific implementations for different DEXes
abstract contract BaseDexVault is BaseDexUniformVault, IERC721Receiver {
    using SafeERC20 for IERC20Metadata;

    /// @notice The ID of the NFT representing the Dex liquidity position
    uint256 public positionTokenId;

    int24 public tickLower;
    int24 public tickUpper;
    uint160 public sqrtPriceLower;
    uint160 public sqrtPriceUpper;

    constructor(address _token0, address _token1) BaseDexUniformVault(_token0, _token1) {}

    /// @notice Initializes the contract with the given admin address
    /// @param admin The address of the admin
    function __BaseDexVault_init(address admin) public onlyInitializing {
        _updateTicks();
        _updateSqrtPricesLowerAndUpper();
        __Ownable_init(admin);
    }

    /// @notice Calculates the amounts neeeded to get swapped into token0 and token1 to place a position in the given range.
    /// @param amount The total assets to be divided between token0 and token1
    function _getAmounts(uint256 amount) internal view override returns (uint256 amountFor0, uint256 amountFor1) {
        uint160 sqrtPriceX96 = getCurrentSqrtPrice();
        if (sqrtPriceX96 <= sqrtPriceLower) {
            amountFor0 = amount;
        } else if (sqrtPriceX96 < sqrtPriceUpper) {
            uint256 n = FullMath.mulDiv(sqrtPriceUpper, sqrtPriceX96 - sqrtPriceLower, FixedPoint96.Q96);
            uint256 d = FullMath.mulDiv(sqrtPriceX96, sqrtPriceUpper - sqrtPriceX96, FixedPoint96.Q96);
            uint256 x = FullMath.mulDiv(n, FixedPoint96.Q96, d);
            amountFor0 = FullMath.mulDiv(amount, FixedPoint96.Q96, x + FixedPoint96.Q96);
            amountFor1 = amount - amountFor0;
        } else {
            amountFor1 = amount;
        }
    }

    /// @notice Retrieves the amounts of token0 and token1 that correspond to the current liquidity
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function getPositionAmounts() public view override returns (uint256 amount0, uint256 amount1) {
        (uint128 owed0, uint128 owed1) = _getTokensOwed();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            getCurrentSqrtPrice(), sqrtPriceLower, sqrtPriceUpper, uint128(_getTokenLiquidity())
        );
        amount0 += owed0;
        amount1 += owed1;
    }

    /// @notice Abstract function to mint a new Dex liquidity position
    /// @dev Must be implemented by the inheriting contract
    /// @param amount0 The amount of token0 to add to the liquidity position
    /// @param amount1 The amount of token1 to add to the liquidity position
    /// @return tokenId The ID of the newly minted liquidity position
    /// @return liquidity The amount of liquidity added
    /// @return amount0Used The amount of token0 used in the liquidity provision
    /// @return amount1Used The amount of token1 used in the liquidity provision
    function _mintPosition(uint256 amount0, uint256 amount1)
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

    function _addLiquidity(uint256 amount0, uint256 amount1)
        internal
        override
        returns (uint256 amount0Used, uint256 amount1Used, uint256 liquidity)
    {
        if (positionTokenId == 0) {
            (positionTokenId, liquidity, amount0Used, amount1Used) = _mintPosition(amount0, amount1);
        } else {
            (liquidity, amount0Used, amount1Used) = _increaseLiquidity(amount0, amount1);
        }
    }

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

    function _removeLiquidity(uint256 liquidity) internal override returns (uint256 amount0, uint256 amount1) {
        uint256 totalLiquidity = _getTokenLiquidity();

        (uint256 liq0, uint256 liq1) = _decreaseLiquidity(uint128(liquidity));
        (uint128 owed0, uint128 owed1) = _getTokensOwed();

        // everything besides just claimed liquidity are fees
        uint256 fees0 = owed0 - liq0;
        uint256 fees1 = owed1 - liq1;
        (amount0, amount1) = _collect(
            uint128(liquidity * fees0 / totalLiquidity + liq0), uint128(liquidity * fees1 / totalLiquidity + liq1)
        );
    }

    /// @notice Retrieves the current liquidity of the Dex position
    /// @return liquidity The current liquidity of the position
    function _getTokenLiquidity() internal view virtual override returns (uint256 liquidity) {
        if (positionTokenId == 0) {
            return 0;
        }

        return _getTokenLiquidity(positionTokenId);
    }

    function _getTokenLiquidity(uint256 tokenId) internal view virtual returns (uint128 liquidity);

    /// @notice Retrieves the amount of tokens owed to the vault from the Dex position
    /// @return amount0 The amount of token0 owed
    /// @return amount1 The amount of token1 owed
    function _getTokensOwed() internal view virtual returns (uint128 amount0, uint128 amount1);

    /// @notice Abstract function to update the current ticks of the Dex pool
    /// @dev Must be implemented by the inheriting contract
    function _updateTicks() internal virtual;

    /// @notice Abstract function to update the current square root prices of the Dex pool
    /// Use only after updating the ticks
    function _updateSqrtPricesLowerAndUpper() internal virtual {
        sqrtPriceLower = TickMath.getSqrtRatioAtTick(tickLower);
        sqrtPriceUpper = TickMath.getSqrtRatioAtTick(tickUpper);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _validateTokenToRecover(address) internal pure override returns (bool) {
        return true;
    }
}
