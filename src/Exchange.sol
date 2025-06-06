// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {OracleData} from "./libraries/OracleData.sol";

/**
 * @title Exchange Contract
 * @notice This contract facilitates buying and selling of CYBRO tokens using USDB or WETH
 */
contract Exchange is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20Metadata;
    using OracleData for IChainlinkOracle;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when tokens are bought
     * @param amount The amount of CYBRO tokens bought
     * @param cost The cost in USDB or WETH
     * @param receiver The address receiving the CYBRO tokens
     * @param buyer The address of the buyer
     */
    event Bought(uint256 amount, uint256 cost, address receiver, address buyer);

    /**
     * @notice Emitted when tokens are sold
     * @param amount The amount of CYBRO tokens sold
     * @param cost The cost received in USDB or WETH
     * @param receiver The address receiving the payment
     * @param seller The address of the seller
     */
    event Sold(uint256 amount, uint256 cost, address receiver, address seller);

    /* ========== CONSTANTS ========== */

    /// @notice Precision used for spread calculations
    uint32 public constant spreadPrecision = 10000;

    /* ========== IMMUTABLE VARIABLES ========== */

    /// @notice The USDB token contract
    IERC20Metadata public immutable USDB;

    /// @notice The WETH token contract
    IERC20Metadata public immutable WETH;

    /// @notice USDB token decimals
    uint8 public immutable decimalsUSDB;

    /// @notice Chainlink oracle for ETH price
    IChainlinkOracle public immutable oracle;

    /// @notice Oracle decimals for ETH price
    uint8 public immutable oracleDecimals;

    /// @notice Custom oracle for CYBRO token price
    IOracle public immutable oracleCybro;

    /// @notice The CYBRO token contract
    IERC20Metadata public immutable cybro;

    /// @notice CYBRO token decimals
    uint8 public immutable decimalsCYBRO;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    uint32 public spread;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the contract with necessary addresses and parameters
     * @param _weth The address of the WETH token
     * @param _usdb The address of the USDB token
     * @param _oracle The address of the oracle for ETH
     * @param _oracleCybro The address of the oracle for CYBRO
     */
    constructor(address _weth, address _usdb, address _oracle, address _oracleCybro) {
        USDB = IERC20Metadata(_usdb);
        WETH = IERC20Metadata(_weth);
        decimalsUSDB = IERC20Metadata(_usdb).decimals();
        oracle = IChainlinkOracle(_oracle);
        oracleDecimals = oracle.decimals();
        oracleCybro = IOracle(_oracleCybro);
        cybro = IERC20Metadata(oracleCybro.cybro());
        decimalsCYBRO = cybro.decimals();
    }

    /* ========== INITIALIZER ========== */

    /**
     * @notice Initializes the contract, setting the admin and initial spread
     * @param admin The address of the admin
     * @param _spread The initial spread to apply to trades
     */
    function initialize(address admin, uint32 _spread) public initializer {
        __Ownable_init(admin);
        spread = _spread;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Buys CYBRO tokens using either USDB or WETH
     * @param amount The amount of CYBRO tokens to buy
     * @param receiver The address to receive CYBRO tokens
     * @param usdbOrWeth Set to true for USDB or false for WETH
     * @return cost The amount of USDB/WETH spend
     */
    function buy(uint256 amount, address receiver, bool usdbOrWeth) external returns (uint256 cost) {
        cost = viewBuyByCybro(amount, usdbOrWeth);
        (usdbOrWeth ? USDB : WETH).safeTransferFrom(msg.sender, address(this), cost);
        cybro.safeTransfer(receiver, amount);

        emit Bought(amount, cost, receiver, msg.sender);
    }

    /**
     * @notice Sells CYBRO tokens for USDB or WETH
     * @param amount The amount of CYBRO tokens to sell
     * @param receiver The address to receive the payment
     * @param usdbOrWeth Set to true for USDB or false for WETH
     * @return cost The cost in USDB or WETH received
     */
    function sell(uint256 amount, address receiver, bool usdbOrWeth) external whenNotPaused returns (uint256 cost) {
        cybro.safeTransferFrom(msg.sender, address(this), amount);
        cost = viewSellByCybro(amount, usdbOrWeth);
        (usdbOrWeth ? USDB : WETH).safeTransfer(receiver, cost);

        emit Sold(amount, cost, receiver, msg.sender);
    }

    /**
     * @notice Pauses selling by users
     * @dev Only callable by the owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses selling by users
     * @dev Only callable by the owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the spread percentage
     * @param _spread The spread percentage
     */
    function setSpread(uint32 _spread) external onlyOwner {
        spread = _spread;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the current CYBRO price with applied spread
     * @param buyOrSell Set to true for buy price, false for sell price
     * @return The price with spread
     */
    function getPriceWithSpread(bool buyOrSell) external view returns (uint256) {
        return _getPriceInUSDB(buyOrSell);
    }

    /**
     * @notice Gets the current price of CYBRO from the oracle
     * @return The current CYBRO price
     */
    function getCybroPrice() public view returns (uint256) {
        return oracleCybro.getPrice();
    }

    /**
     * @notice Computes how much CYBRO can be bought with a given amount of USDB or WETH
     * @param amount The amount of USDB or WETH
     * @param usdbOrWeth True if using USDB, false if using WETH
     * @return The amount of CYBRO tokens
     */
    function viewBuyByToken(uint256 amount, bool usdbOrWeth) external view returns (uint256) {
        return _getTokensAmount(usdbOrWeth ? amount : _convertETHToUSDB(amount), true);
    }

    /**
     * @notice Computes how much CYBRO needs to be sold to receive a given amount of USDB or WETH
     * @param amount The amount of USDB or WETH
     * @param usdbOrWeth True if receiving USDB, false if receiving WETH
     * @return The amount of CYBRO tokens
     */
    function viewSellByToken(uint256 amount, bool usdbOrWeth) external view returns (uint256) {
        return _getTokensAmount(usdbOrWeth ? amount : _convertETHToUSDB(amount), false);
    }

    /**
     * @notice Computes the cost in USDB or WETH to buy a given amount of CYBRO
     * @param amount The amount of CYBRO tokens
     * @param usdbOrWeth True if using USDB, false if using WETH
     * @return The cost in USDB or WETH
     */
    function viewBuyByCybro(uint256 amount, bool usdbOrWeth) public view returns (uint256) {
        uint256 usdbCost = _getCostInUSDB(amount, true);
        return usdbOrWeth ? usdbCost : _convertUSDBToETH(usdbCost);
    }

    /**
     * @notice Computes how much USDB or WETH will be received for selling a given amount of CYBRO
     * @param amount The amount of CYBRO tokens
     * @param usdbOrWeth True if receiving USDB, false if receiving WETH
     * @return The amount of USDB or WETH
     */
    function viewSellByCybro(uint256 amount, bool usdbOrWeth) public view returns (uint256) {
        uint256 usdbCost = _getCostInUSDB(amount, false);
        return usdbOrWeth ? usdbCost : _convertUSDBToETH(usdbCost);
    }

    /**
     * @notice Maximum amount of CYBRO tokens available to buy
     * @return The CYBRO token balance of the contract
     */
    function maxAmountToBuy() external view returns (uint256) {
        return cybro.balanceOf(address(this));
    }

    /**
     * @notice Maximum amount of CYBRO tokens that can be sold based on available liquidity
     * @param usdbOrWeth True if liquidity in USDB, false if in WETH
     * @return The amount of CYBRO tokens
     */
    function maxAmountToSell(bool usdbOrWeth) external view returns (uint256) {
        return usdbOrWeth
            ? _getTokensAmount(USDB.balanceOf(address(this)), false)
            : _getTokensAmount(_convertETHToUSDB(WETH.balanceOf(address(this))), false);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Calculates amount of CYBRO tokens for given payment amount
     * @param amount The amount of payment token (USDB or WETH)
     * @param buyOrSell True for buy calculation, false for sell calculation
     * @return The amount of CYBRO tokens
     */
    function _getTokensAmount(uint256 amount, bool buyOrSell) internal view returns (uint256) {
        return amount * (10 ** decimalsCYBRO) / _getPriceInUSDB(buyOrSell);
    }

    /**
     * @dev Calculates cost in USDB for given amount of CYBRO tokens
     * @param amount The amount of CYBRO tokens
     * @param buyOrSell True for buy calculation, false for sell calculation
     * @return Cost in USDB
     */
    function _getCostInUSDB(uint256 amount, bool buyOrSell) internal view returns (uint256) {
        return amount * _getPriceInUSDB(buyOrSell) / (10 ** decimalsCYBRO);
    }

    /**
     * @dev Returns current CYBRO price in USDB with applied spread
     * @param buyOrSell True for buy price, false for sell price
     * @return Price with spread in USDB
     */
    function _getPriceInUSDB(bool buyOrSell) internal view returns (uint256) {
        return getCybroPrice() * (buyOrSell ? (spread + spreadPrecision) : (spreadPrecision - spread)) / spreadPrecision;
    }

    /**
     * @dev Converts ETH amount to equivalent USDB amount using oracle price
     * @param volume The amount of ETH to convert
     * @return Equivalent amount in USDB
     */
    function _convertETHToUSDB(uint256 volume) private view returns (uint256) {
        return _getETHPrice() * volume * (10 ** decimalsUSDB) / (10 ** oracleDecimals) / (10 ** 18);
    }

    /**
     * @dev Converts USDB amount to equivalent ETH amount using oracle price
     * @param volume The amount of USDB to convert
     * @return Equivalent amount in ETH
     */
    function _convertUSDBToETH(uint256 volume) private view returns (uint256) {
        return volume * 1e18 * (10 ** oracleDecimals) / (_getETHPrice() * (10 ** decimalsUSDB));
    }

    /**
     * @dev Fetches ETH price from oracle, with safety checks for freshness and validity
     * @return Current ETH price from oracle
     */
    function _getETHPrice() private view returns (uint256) {
        return oracle.getPrice();
    }

    /**
     * @notice Allows owner to withdraw tokens from the contract
     * @param token The address of the token to withdraw (zero address for ETH)
     */
    function withdrawFunds(address token) external virtual onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "failed to send ETH");
        } else {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        }
    }
}
