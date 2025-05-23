// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {IBlasterswapV2Router02} from "../interfaces/blaster/IBlasterswapV2Router02.sol";
import {IBlasterswapV2Factory} from "../interfaces/blaster/IBlasterswapV2Factory.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseDexUniformVault, IERC20Metadata} from "./BaseDexUniformVault.sol";
import {IBlasterswapV2Pair} from "../interfaces/blaster/IBlasterswapV2Pair.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";
import {BaseVault} from "../BaseVault.sol";
import {DexPriceCheck} from "../libraries/DexPriceCheck.sol";

/**
 * @title BlasterSwapV2Vault
 * @notice This contract manages liquidity provision on the BlasterSwap V2 decentralized exchange (DEX)
 * @dev Inherits from the BaseDexUniformVault and provides specific implementation for BlasterSwap V2
 */
contract BlasterSwapV2Vault is BaseDexUniformVault {
    using SafeERC20 for IERC20Metadata;

    /* ========== IMMUTABLE VARIABLES ========== */

    /// @notice The router used to interact with the BlasterSwap V2 DEX
    IBlasterswapV2Router02 public immutable router;

    /// @notice The LP (liquidity provider) token that represents the liquidity pool on BlasterSwap V2
    IBlasterswapV2Pair public immutable lpToken;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Constructor that initializes the BlasterSwap V2 vault
     * @param _router The address of the BlasterSwap V2 router
     * @param _token0 The address of token0 in the liquidity pool
     * @param _token1 The address of token1 in the liquidity pool
     * @param _asset The base token of the vault
     * @param _feeProvider The fee provider contract
     * @param _feeRecipient The address that receives the fees
     */
    constructor(
        address payable _router,
        address _token0,
        address _token1,
        IERC20Metadata _asset,
        IFeeProvider _feeProvider,
        address _feeRecipient,
        address _oracleToken0,
        address _oracleToken1
    ) BaseDexUniformVault(_token0, _token1, _asset, _feeProvider, _feeRecipient, _oracleToken0, _oracleToken1) {
        require(address(oracleToken0) != address(0) && address(oracleToken1) != address(0), OracleNotSet());
        router = IBlasterswapV2Router02(_router);
        lpToken = IBlasterswapV2Pair(IBlasterswapV2Factory(router.factory()).getPair(token0, token1));

        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the contract with admin address, token name, and symbol
     * @param admin The address of the admin
     * @param manager The address of the manager
     * @param name The name of the ERC20 token representing the vault shares
     * @param symbol The symbol of the ERC20 token representing the vault shares
     */
    function initialize(address admin, address manager, string memory name, string memory symbol) public initializer {
        IERC20Metadata(token0).forceApprove(address(router), type(uint256).max);
        IERC20Metadata(token1).forceApprove(address(router), type(uint256).max);
        IERC20Metadata(address(lpToken)).forceApprove(address(router), type(uint256).max);
        __ERC20_init(name, symbol);
        __BaseDexUniformVault_init(admin, manager);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @inheritdoc BaseDexUniformVault
    function getCurrentSqrtPrice() public view virtual override returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = lpToken.getReserves();
        return Math.sqrt(reserve1) * Math.sqrt(2 ** 192 / reserve0);
    }

    /// @inheritdoc BaseDexUniformVault
    function getPositionAmounts() public view override returns (uint256 amount0, uint256 amount1) {
        (uint112 reserve0, uint112 reserve1,) = lpToken.getReserves();
        uint256 totalSupply_ = lpToken.totalSupply();
        uint256 liquidity = _getTokenLiquidity();
        amount0 = liquidity * reserve0 / totalSupply_;
        amount1 = liquidity * reserve1 / totalSupply_;
    }

    function underlyingTVL() external view override returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = lpToken.getReserves();
        uint256 sqrtPrice = _getTrustedSqrtPrice();
        return isToken0
            ? reserve0 + Math.mulDiv(reserve1, 2 ** 192, sqrtPrice * sqrtPrice)
            : reserve1 + Math.mulDiv(reserve0, sqrtPrice * sqrtPrice, 2 ** 192);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _getTrustedSqrtPrice() internal view override returns (uint256) {
        return DexPriceCheck.getSqrtPriceFromOracles(oracleToken0, oracleToken1, token0, token1);
    }

    /// @inheritdoc BaseDexUniformVault
    function _checkPriceManipulation() internal view override {
        DexPriceCheck.checkPriceManipulation(
            oracleToken0, oracleToken1, token0, token1, false, address(0), getCurrentSqrtPrice()
        );
    }

    /// @inheritdoc BaseDexUniformVault
    function _getAmounts(uint256 amount) internal pure override returns (uint256 amountFor0, uint256 amountFor1) {
        amountFor0 = amount / 2;
        amountFor1 = amount - amountFor0;
    }

    /// @inheritdoc BaseDexUniformVault
    function _getTokenLiquidity() internal view override returns (uint256) {
        return lpToken.balanceOf(address(this));
    }

    /// @inheritdoc BaseDexUniformVault
    function _swap(bool zeroForOne, uint256 amount) internal virtual override returns (uint256) {
        address[] memory path = new address[](2);
        (path[0], path[1]) = zeroForOne ? (token0, token1) : (token1, token0);

        return router.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp)[1];
    }

    /// @inheritdoc BaseDexUniformVault
    function _addLiquidity(uint256 amount0, uint256 amount1)
        internal
        virtual
        override
        returns (uint256 amount0Used, uint256 amount1Used)
    {
        // Add liquidity to the BlasterSwap V2 DEX and return the amounts of tokens used
        (amount0Used, amount1Used,) =
            router.addLiquidity(token0, token1, amount0, amount1, 0, 0, address(this), block.timestamp);
    }

    /// @inheritdoc BaseDexUniformVault
    function _removeLiquidity(uint256 liquidity) internal virtual override returns (uint256 amount0, uint256 amount1) {
        // Remove liquidity from the BlasterSwap V2 DEX and return the amounts of tokens received
        (amount0, amount1) = router.removeLiquidity(token0, token1, liquidity, 0, 0, address(this), block.timestamp);
    }

    /**
     * @inheritdoc BaseVault
     * @dev This function prevents the recovery of LP tokens to avoid disrupting the liquidity management
     */
    function _validateTokenToRecover(address token) internal virtual override(BaseVault) returns (bool) {
        return token != address(lpToken);
    }
}
