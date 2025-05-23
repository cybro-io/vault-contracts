// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {BaseDexUniformVault} from "./BaseDexUniformVault.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {BaseVault} from "../BaseVault.sol";

/**
 * @title BaseDexVault
 * @notice This abstract contract provides a base implementation for managing liquidity on a decentralized exchange (Dex)
 * @dev This contract is meant to be inherited by specific implementations for different DEXes
 */
abstract contract BaseDexVault is BaseDexUniformVault, IERC721Receiver {
    using SafeERC20 for IERC20Metadata;

    /// @custom:storage-location erc7201:cybro.storage.BaseDexVault
    struct BaseDexVaultStorage {
        uint256 positionTokenId;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceLower;
        uint160 sqrtPriceUpper;
    }

    function _getBaseDexVaultStorage() private pure returns (BaseDexVaultStorage storage $) {
        assembly {
            $.slot := BASE_DEX_VAULT_STORAGE_LOCATION
        }
    }

    // keccak256(abi.encode(uint256(keccak256("cybro.storage.BaseDexVault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASE_DEX_VAULT_STORAGE_LOCATION =
        0x29bf470113e700e8de784ff86fa6f291763217c272e1254db191a93543cce800;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _token0,
        address _token1,
        IERC20Metadata _asset,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        address _oracleToken0,
        address _oracleToken1
    ) BaseDexUniformVault(_token0, _token1, _asset, _feeProvider, _feeRecipient, _oracleToken0, _oracleToken1) {}

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the contract
     * @param admin The address of the admin
     * @param manager The address of the manager
     */
    function __BaseDexVault_init(address admin, address manager) public onlyInitializing {
        __BaseDexUniformVault_init(admin, manager);
        _updateTicks();
        _updateSqrtPricesLowerAndUpper();
    }

    /* ========== VIEW FUNCTIONS ========== */

    function positionTokenId() public view returns (uint256) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        return $.positionTokenId;
    }

    function sqrtPriceLower() public view returns (uint160) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        return $.sqrtPriceLower;
    }

    function sqrtPriceUpper() public view returns (uint160) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        return $.sqrtPriceUpper;
    }

    function tickLower() public view returns (int24) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        return $.tickLower;
    }

    function tickUpper() public view returns (int24) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        return $.tickUpper;
    }

    /**
     * @notice Retrieves the amounts of token0 and token1 that correspond to the current liquidity
     * @return amount0 The amount of token0
     * @return amount1 The amount of token1
     */
    function getPositionAmounts() public view override returns (uint256 amount0, uint256 amount1) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        (uint128 owed0, uint128 owed1) = _getTokensOwed();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(getCurrentSqrtPrice()), $.sqrtPriceLower, $.sqrtPriceUpper, uint128(_getTokenLiquidity())
        );
        amount0 += owed0;
        amount1 += owed1;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @inheritdoc BaseDexUniformVault
    function _getAmounts(uint256 amount) internal view override returns (uint256 amountFor0, uint256 amountFor1) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        uint256 sqrtPriceX96 = getCurrentSqrtPrice();
        if (sqrtPriceX96 <= $.sqrtPriceLower) {
            amountFor0 = amount;
        } else if (sqrtPriceX96 < $.sqrtPriceUpper) {
            uint256 n = FullMath.mulDiv($.sqrtPriceUpper, sqrtPriceX96 - $.sqrtPriceLower, FixedPoint96.Q96);
            uint256 d = FullMath.mulDiv(sqrtPriceX96, $.sqrtPriceUpper - sqrtPriceX96, FixedPoint96.Q96);
            uint256 x = FullMath.mulDiv(n, FixedPoint96.Q96, d);
            amountFor0 = FullMath.mulDiv(amount, FixedPoint96.Q96, x + FixedPoint96.Q96);
            amountFor1 = amount - amountFor0;
        } else {
            amountFor1 = amount;
        }
    }

    /**
     * @notice Abstract function to mint a new Dex liquidity position
     * @dev Must be implemented by the inheriting contract
     * @param amount0 The amount of token0 to add to the liquidity position
     * @param amount1 The amount of token1 to add to the liquidity position
     * @return tokenId The ID of the newly minted liquidity position
     * @return amount0Used The amount of token0 used in the liquidity provision
     * @return amount1Used The amount of token1 used in the liquidity provision
     */
    function _mintPosition(uint256 amount0, uint256 amount1)
        internal
        virtual
        returns (uint256 tokenId, uint256 amount0Used, uint256 amount1Used);

    /**
     * @notice Abstract function to increase the liquidity of an existing Dex position
     * @dev Must be implemented by the inheriting contract
     * @param amount0 The amount of token0 to add to the liquidity position
     * @param amount1 The amount of token1 to add to the liquidity position
     * @return amount0Used The amount of token0 used in the liquidity provision
     * @return amount1Used The amount of token1 used in the liquidity provision
     */
    function _increaseLiquidity(uint256 amount0, uint256 amount1)
        internal
        virtual
        returns (uint256 amount0Used, uint256 amount1Used);

    /// @inheritdoc BaseDexUniformVault
    function _addLiquidity(uint256 amount0, uint256 amount1)
        internal
        override
        returns (uint256 amount0Used, uint256 amount1Used)
    {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        if ($.positionTokenId == 0) {
            ($.positionTokenId, amount0Used, amount1Used) = _mintPosition(amount0, amount1);
        } else {
            (amount0Used, amount1Used) = _increaseLiquidity(amount0, amount1);
        }
    }

    /**
     * @notice Abstract function to decrease the liquidity of an existing Dex position
     * @dev Must be implemented by the inheriting contract
     * @param liquidity The amount of liquidity to remove from the position
     * @return amount0 The amount of token0 received from decreasing liquidity
     * @return amount1 The amount of token1 received from decreasing liquidity
     */
    function _decreaseLiquidity(uint128 liquidity) internal virtual returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Abstract function to collect fees earned by the Dex position
     * @dev Must be implemented by the inheriting contract
     * @param amountMax0 The maximum amount of token0 to collect
     * @param amountMax1 The maximum amount of token1 to collect
     * @return amount0 The amount of token0 collected
     * @return amount1 The amount of token1 collected
     */
    function _collect(uint128 amountMax0, uint128 amountMax1)
        internal
        virtual
        returns (uint256 amount0, uint256 amount1);

    /// @inheritdoc BaseDexUniformVault
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

    /// @inheritdoc BaseDexUniformVault
    function _getTokenLiquidity() internal view virtual override returns (uint256 liquidity) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        if ($.positionTokenId == 0) {
            return 0;
        }

        return _getTokenLiquidity($.positionTokenId);
    }

    function _getTokenLiquidity(uint256 tokenId) internal view virtual returns (uint128 liquidity);

    /**
     * @notice Retrieves the amount of tokens owed to the vault from the Dex position
     * @dev If the position is not initialized, returns (0, 0)
     * @return amount0 The amount of token0 owed
     * @return amount1 The amount of token1 owed
     */
    function _getTokensOwed() internal view returns (uint128 amount0, uint128 amount1) {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        if ($.positionTokenId == 0) {
            return (0, 0);
        }

        return _getTokensOwed($.positionTokenId);
    }

    function _getTokensOwed(uint256 tokenId) internal view virtual returns (uint128 amount0, uint128 amount1);

    /// @notice Abstract function to update the current ticks of the Dex pool
    /// @dev Must be implemented by the inheriting contract
    function _updateTicks() internal virtual;

    function _setTicks(int24 _tickLower, int24 _tickUpper) internal {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        $.tickLower = _tickLower;
        $.tickUpper = _tickUpper;
    }

    /// @notice Abstract function to update the current square root prices of the Dex pool
    /// Use only after updating the ticks
    function _updateSqrtPricesLowerAndUpper() internal virtual {
        BaseDexVaultStorage storage $ = _getBaseDexVaultStorage();
        $.sqrtPriceLower = TickMath.getSqrtRatioAtTick($.tickLower);
        $.sqrtPriceUpper = TickMath.getSqrtRatioAtTick($.tickUpper);
    }

    /// @inheritdoc BaseVault
    function _validateTokenToRecover(address) internal pure override returns (bool) {
        return true;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
