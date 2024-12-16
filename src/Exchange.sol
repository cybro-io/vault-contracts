// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {IOracle} from "./interfaces/IOracle.sol";

contract Exchange is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20Metadata;

    /* ========== EVENTS ========== */

    event Bought( uint256 tokensAmount, uint256 usdbCost, address receiver, address buyer);
    event Sold(uint256 tokensAmount, uint256 usdbCost, address receiver, address seller);

    /* ========== CONSTANTS ========== */

    uint32 public constant slippagePrecision = 10000;

    /* ========== IMMUTABLE VARIABLES ========== */

    IERC20Metadata public immutable USDB;
    IERC20Metadata public immutable WETH;
    uint8 public immutable decimalsUSDB;
    IChainlinkOracle public immutable oracle;
    uint8 public immutable oracleDecimals;
    IOracle public immutable oracleCybro;
    IERC20Metadata public immutable cybro;
    uint8 public immutable decimalsCYBRO;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    uint32 public slippage;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _weth, address _usdb, address _oracle, address _oracleCybro) {
        USDB = IERC20Metadata(_usdb);
        WETH = IERC20Metadata(_weth);
        decimalsUSDB = IERC20Metadata(_usdb).decimals();
        oracle = IChainlinkOracle(_oracle);
        oracleDecimals = 8;
        oracleCybro = IOracle(_oracleCybro);
        cybro = IERC20Metadata(oracleCybro.cybro());
        decimalsCYBRO = cybro.decimals();
    }

    /* ========== INITIALIZER ========== */

    function initialize(address admin, uint32 _slippage) public initializer {
        __Ownable_init(admin);
        slippage = _slippage;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice buys tokensAmount of cybro
     * @param amount amount of USDB or WETH
     */
    function buy(uint256 amount, address receiver, bool usdbOrWeth) external returns (uint256 tokensAmount) {
        if (usdbOrWeth) {
            tokensAmount = amount;
            USDB.safeTransferFrom(msg.sender, address(this), amount);
        } else {
            tokensAmount = _convertETHToUSDB(amount);
            WETH.safeTransferFrom(msg.sender, address(this), amount);
        }

        tokensAmount = _getTokensAmount(tokensAmount, true);
        cybro.safeTransfer(receiver, tokensAmount);

        emit Bought(tokensAmount, amount, receiver, msg.sender);
    }

    /**
     * @notice sells tokensAmount of cybro
     * @param amount amount of CYBRO tokens to sell
     */
    function sell(uint256 amount, address receiver, bool usdbOrWeth) external whenNotPaused returns (uint256 usdbCost) {
        usdbCost = _getCostInUSDB(amount, false);
        cybro.safeTransferFrom(msg.sender, address(this), amount);

        if (usdbOrWeth) {
            USDB.safeTransfer(receiver, usdbCost);
        } else {
            WETH.safeTransfer(receiver, _convertUSDBToETH(usdbCost));
        }

        emit Sold(amount, usdbCost, receiver, msg.sender);
    }

    /// @notice Pauses the vault
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the vault
    function unpause() external onlyOwner {
        _unpause();
    }

    function setSlippage(uint32 _slippage) external onlyOwner {
        slippage = _slippage;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getPriceWithSlippage(bool buyOrSell) external view returns (uint256) {
        return _getPriceInUSDB(buyOrSell);
    }

    function getCybroPrice() public view returns (uint256) {
        return oracleCybro.getPrice();
    }

    // how much cybro u will get for amount of USDB or WETH
    function viewBuyByToken(uint256 amount, bool usdbOrWeth) external view returns (uint256) {
        return _getTokensAmount(usdbOrWeth ? amount : _convertETHToUSDB(amount), true);
    }

    // how much u need to pay for amount of cybro
    function viewBuyByCybro(uint256 amount, bool usdbOrWeth) external view returns (uint256) {
        uint256 usdbCost = _getCostInUSDB(amount, true);
        return usdbOrWeth ? usdbCost : _convertUSDBToETH(usdbCost);
    }

    // how much u will get for amount of cybro
    function viewSellByCybro(uint256 amount, bool usdbOrWeth) external view returns (uint256) {
        uint256 usdbCost = _getCostInUSDB(amount, false);
        return usdbOrWeth ? usdbCost : _convertUSDBToETH(usdbCost);
    }

    // how much cybro u need to sell for amount of USDB or WETH
    function viewSellByToken(uint256 amount, bool usdbOrWeth) external view returns (uint256) {
        return _getTokensAmount(usdbOrWeth ? amount : _convertETHToUSDB(amount), false);
    }

    function maxAmountToBuy() external view returns (uint256) {
        return cybro.balanceOf(address(this));
    }

    function maxAmountToSell(bool usdbOrWeth) external view returns (uint256) {
        return usdbOrWeth
            ? _getTokensAmount(USDB.balanceOf(address(this)), false)
            : _getTokensAmount(_convertETHToUSDB(WETH.balanceOf(address(this))), false);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    // amount - of token
    function _getTokensAmount(uint256 amount, bool buyOrSell) internal view returns (uint256) {
        return amount * (10 ** decimalsCYBRO) / _getPriceInUSDB(buyOrSell);
    }

    // amount - of cybro
    function _getCostInUSDB(uint256 amount, bool buyOrSell) internal view returns (uint256) {
        return amount * _getPriceInUSDB(buyOrSell) / (10 ** decimalsCYBRO);
    }

    function _getPriceInUSDB(bool buyOrSell) internal view returns (uint256) {
        return getCybroPrice() * (buyOrSell ? (slippage + slippagePrecision) : (slippagePrecision - slippage))
            / slippagePrecision;
    }

    /// @notice Converts given amount of ETH to USDB, using oracle price
    function _convertETHToUSDB(uint256 volume) private view returns (uint256) {
        return _getETHPrice() * volume * (10 ** decimalsUSDB) / (10 ** oracleDecimals) / (10 ** 18);
    }

    /// @notice Converts given amount of USDB to ETH, using oracle price
    function _convertUSDBToETH(uint256 volume) private view returns (uint256) {
        return volume * 1e18 * (10 ** oracleDecimals) / (_getETHPrice() * (10 ** decimalsUSDB));
    }

    /// @notice Fetches ETH price from oracle, performing additional safety checks to ensure the oracle is healthy.
    function _getETHPrice() private view returns (uint256) {
        (uint80 roundID, int256 price,, uint256 timestamp, uint80 answeredInRound) = oracle.latestRoundData();
        require(answeredInRound >= roundID, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink price reporting 0");

        return uint256(price);
    }

    /// @notice Withdraws funds
    /// @param token The address of the token to withdraw
    function withdrawFunds(address token) external virtual onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "failed to send ETH");
        } else {
            IERC20Metadata(token).safeTransfer(msg.sender, IERC20Metadata(token).balanceOf(address(this)));
        }
    }
}
