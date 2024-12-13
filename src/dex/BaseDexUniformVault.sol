// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IDexVault} from "../interfaces/IDexVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

/// @title BaseDexUniformVault
/// @notice This abstract contract provides a base implementation for managing liquidity on a decentralized exchange (DEX)
/// @dev This contract is meant to be inherited by specific implementations for different DEXes
abstract contract BaseDexUniformVault is ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable, IDexVault {
    using SafeERC20 for IERC20Metadata;

    /// @dev Custom error that is thrown when attempting to withdraw an invalid token.
    error InvalidTokenToWithdraw(address token);

    /* ========== EVENTS ========== */

    /// @notice Emitted when liquidity is deposited into the vault
    /// @param sender The address initiating the deposit
    /// @param owner The address that receives the vault tokens
    /// @param liquidity The amount of liquidity added
    /// @param shares The number of shares minted to the owner
    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 liquidity,
        uint256 shares,
        uint256 depositFee,
        uint256 totalSupplyBefore,
        uint256 tvlBefore
    );

    /// @notice Emitted when liquidity is withdrawn from the vault
    /// @param sender The address initiating the withdrawal
    /// @param receiver The address receiving the withdrawn tokens
    /// @param owner The address of the owner of the shares being redeemed
    /// @param shares The number of shares burned from the owner
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 shares,
        uint256 withdrawalFee,
        uint256 totalSupplyBefore,
        uint256 tvlBefore
    );

    event PerformanceFeeCollected(address indexed owner, uint256 fee);

    /* ========== CONSTANTS ========== */

    /// @notice Role identifier for managers
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /* ========== IMMUTABLE VARIABLES ========== */

    address public immutable token0;
    address public immutable token1;
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;
    uint8 private immutable _decimals;

    /// @notice Indicates which token is base token
    bool public immutable zeroOrOne;

    /// @notice The fee provider contract
    IFeeProvider public immutable feeProvider;

    /// @notice The address that receives the fees
    address public immutable feeRecipient;

    /// @notice The precision used for fee calculations
    uint32 public immutable feePrecision;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice Mapping of account addresses to their deposited balance of assets
    mapping(address account => uint256) internal _waterline;

    /* ========== CONSTRUCTOR ========== */

    /// @notice Constructor that sets the initial token addresses and their respective decimals
    /// @param _token0 The address of token0
    /// @param _token1 The address of token1
    constructor(address _token0, address _token1, bool _zeroOrOne, IFeeProvider _feeProvider, address _feeRecipient) {
        (token0, token1, zeroOrOne) =
            _token0 < _token1 ? (_token0, _token1, _zeroOrOne) : (_token1, _token0, !_zeroOrOne);
        token0Decimals = IERC20Metadata(token0).decimals();
        token1Decimals = IERC20Metadata(token1).decimals();
        _decimals = (zeroOrOne ? token0Decimals : token1Decimals);
        if (address(_feeProvider) != address(0)) {
            feeProvider = _feeProvider;
            feeRecipient = _feeRecipient;
            feePrecision = feeProvider.getFeePrecision();
        }
    }

    /* ========== INITIALIZER ========== */

    /// @notice Initializes the contract with the given admin address
    /// @dev This function should be called once during deployment to set up the ownership
    /// @param admin The address of the admin
    /// @param manager The address of the manager
    function __BaseDexUniformVault_init(address admin, address manager) public onlyInitializing {
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MANAGER_ROLE, manager);
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /// @notice Pauses the vault
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the vault
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Deposits liquidity into the vault by swapping and adding tokens to the DEX
    /// @return shares The number of shares minted for the deposited liquidity
    function deposit(uint256 assets, address receiver, uint256 minShares)
        public
        whenNotPaused
        returns (uint256 shares)
    {
        IERC20Metadata(zeroOrOne ? token0 : token1).safeTransferFrom(msg.sender, address(this), assets);
        uint256 depositFee;
        (assets, depositFee) = address(feeProvider) == address(0) ? (assets, 0) : _applyDepositFee(assets);

        (uint256 amount0, uint256 amount1) = _getAmounts(assets);

        if (zeroOrOne) {
            amount0 = amount0;
            amount1 = _swap(true, amount1);
        } else {
            amount0 = _swap(false, amount0);
            amount1 = amount1;
        }

        (uint256 amount0Used, uint256 amount1Used, uint256 liquidityReceived) = _addLiquidity(amount0, amount1);

        // Calculate remaining amounts after liquidity provision
        amount0 -= amount0Used;
        amount1 -= amount1Used;

        uint256 deposited = _calculateInBaseToken(amount0Used, amount1Used);
        uint256 totalSupplyBefore = totalSupply();
        uint256 tvlBefore;
        if (totalSupplyBefore == 0) {
            tvlBefore = 0;
            shares = deposited;
        } else {
            tvlBefore = totalAssets() - deposited;
            shares = totalSupplyBefore * deposited / tvlBefore;
        }

        require(shares >= minShares, "minShares");

        _waterline[receiver] += deposited;

        _mint(receiver, shares);

        // Handle remaining tokens and return them to the user if necessary
        if (amount0 > 0 && !zeroOrOne) {
            amount1 += _swap(true, amount0);
            IERC20Metadata(token1).safeTransfer(msg.sender, amount1);
        } else if (amount1 > 0 && zeroOrOne) {
            amount0 += _swap(false, amount1);
            IERC20Metadata(token0).safeTransfer(msg.sender, amount0);
        } else {
            if (zeroOrOne && amount0 > 0) {
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
        if (zeroOrOne) {
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

        IERC20Metadata(zeroOrOne ? token0 : token1).safeTransfer(receiver, assets);

        emit Withdraw(_msgSender(), receiver, owner, shares, withdrawalFee, totalSupplyBefore, tvlBefore);
    }

    /// @notice Allows the owner to withdraw funds accidentally sent to the contract
    /// @dev This function can only be called by the owner of the contract
    /// @param token The address of the token to withdraw, or address(0) for ETH
    function withdrawFunds(address token) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "failed to send ETH");
        } else if (_validateTokenToRecover(token)) {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        } else {
            revert InvalidTokenToWithdraw(token);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Returns the number of decimals of the vault's shares
    function decimals() public view override(IERC20Metadata, ERC20Upgradeable) returns (uint8) {
        return _decimals;
    }

    /// @notice Returns the withdrawal fee for an account
    /// @param account The address of the account
    function quoteWithdrawalFee(address account) external view returns (uint256) {
        uint256 assets = getBalanceInUnderlying(account);
        uint256 waterline = _waterline[account];
        uint256 _fee;
        if (assets > waterline) {
            _fee = (assets - waterline) * feeProvider.getPerformanceFee(account) / feePrecision;
        }

        return _fee + ((assets - _fee) * feeProvider.getWithdrawalFee(account)) / feePrecision;
    }

    /// @notice Returns the waterline of an account
    /// @param account The address of the account
    function getWaterline(address account) external view returns (uint256) {
        return _waterline[account];
    }

    /// @notice Returns the balance in underlying assets of an account
    /// @param account The address of the account
    function getBalanceInUnderlying(address account) public view returns (uint256) {
        return balanceOf(account) * sharePrice() / 10 ** decimals();
    }

    /// @notice Returns the profit of an account
    /// @param account The address of the account
    function getProfit(address account) external view returns (uint256) {
        uint256 balance = getBalanceInUnderlying(account);
        return balance > _waterline[account] ? balance - _waterline[account] : 0;
    }

    /// @notice Returns the deposit fee for an account
    /// @param account The address of the account
    function getDepositFee(address account) external view returns (uint256) {
        return feeProvider.getDepositFee(account);
    }

    /// @notice Returns the withdrawal fee for an account
    /// @param account The address of the account
    function getWithdrawalFee(address account) external view returns (uint256) {
        return feeProvider.getWithdrawalFee(account);
    }

    /// @notice Returns the performance fee for an account
    /// @param account The address of the account
    function getPerformanceFee(address account) external view returns (uint256) {
        return feeProvider.getPerformanceFee(account);
    }

    /// @notice Retrieves the amounts of token0 and token1 that correspond to the current liquidity
    /// @dev Must be implemented by the inheriting contract to provide specific logic for the DEX
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function getPositionAmounts() public view virtual returns (uint256 amount0, uint256 amount1);

    /// @notice Abstract function to retrieve the current square root price of the Dex pool
    /// @dev Must be implemented by the inheriting contract
    /// @return The current square root price
    function getCurrentSqrtPrice() public view virtual override returns (uint160);

    function totalAssets() public view returns (uint256 totalValue) {
        (uint256 total0, uint256 total1) = getPositionAmounts();
        totalValue = _calculateInBaseToken(total0, total1);
    }

    function sharePrice() public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? (10 ** _decimals) : totalAssets() * (10 ** _decimals) / supply;
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

    /// @dev Divides amounts for liquidity provision through _addLiquidity
    function _getAmounts(uint256 amount) internal view virtual returns (uint256 amountFor0, uint256 amountFor1);

    function _calculateInBaseToken(uint256 amount0, uint256 amount1) internal view returns (uint256) {
        uint256 sqrtPrice = uint256(getCurrentSqrtPrice());
        return zeroOrOne
            ? Math.mulDiv(amount1, 2 ** 192, sqrtPrice * sqrtPrice) + amount0
            : Math.mulDiv(amount0, sqrtPrice * sqrtPrice, 2 ** 192) + amount1;
    }

    /// @dev Internal function to validate whether a token can be recovered by the owner
    /// @param token The address of the token to validate
    /// @return A boolean indicating whether the token can be recovered
    function _validateTokenToRecover(address token) internal virtual returns (bool);

    function _applyDepositFee(uint256 assets) internal returns (uint256, uint256) {
        uint256 _fee = (assets * feeProvider.getDepositFee(msg.sender)) / feePrecision;
        if (_fee > 0) {
            assets -= _fee;
            IERC20Metadata(zeroOrOne ? token0 : token1).safeTransfer(feeRecipient, _fee);
        }
        return (assets, _fee);
    }

    function _applyWithdrawalFee(uint256 assets, address owner) internal returns (uint256, uint256) {
        uint256 _fee = (assets * feeProvider.getWithdrawalFee(owner)) / feePrecision;
        if (_fee > 0) {
            assets -= _fee;
            IERC20Metadata(zeroOrOne ? token0 : token1).safeTransfer(feeRecipient, _fee);
        }
        return (assets, _fee);
    }

    function _applyPerformanceFee(uint256 assets, uint256 shares, address owner) internal returns (uint256, uint256) {
        uint256 balancePortion = _waterline[owner] * shares / balanceOf(owner);
        _waterline[owner] -= balancePortion;
        uint256 _fee;
        if (assets > balancePortion) {
            _fee = (assets - balancePortion) * feeProvider.getPerformanceFee(owner) / feePrecision;
            IERC20Metadata(zeroOrOne ? token0 : token1).safeTransfer(feeRecipient, _fee);
        }
        emit PerformanceFeeCollected(owner, _fee);
        return (assets - _fee, _fee);
    }
}
