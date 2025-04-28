// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IOracle} from "./interfaces/IOracle.sol";

/**
 * @title Oracle Contract
 * @notice This contract provides a price feed for CYBRO tokens in terms of USDB
 * @dev Prices can be updated by the owner and are stored internally
 */
contract Oracle is OwnableUpgradeable, IOracle {
    using SafeERC20 for IERC20Metadata;

    /// @notice Thrown when an incorrect or unset price is queried
    error IncorrectPrice();

    /// @notice Emitted when the CYBRO price is updated
    /// @param newPrice The new CYBRO token price
    event PriceUpdated(uint256 newPrice);

    /// @notice Actual price of CYBRO in USD
    uint256 internal _price;

    /// @notice The CYBRO token contract
    address public immutable cybro;

    /// @notice The USDB token contract
    address public immutable usdb;

    constructor(address _cybro, address _usdb) {
        cybro = _cybro;
        usdb = _usdb;
    }

    function initialize(address admin) public initializer {
        __Ownable_init(admin);
    }

    /**
     * @notice Updates the stored price of CYBRO tokens
     * @param price The new price to be set
     * @dev Only the owner can call this function
     */
    function updatePrice(uint256 price) external onlyOwner {
        _price = price;
        emit PriceUpdated(price);
    }

    /**
     * @notice Retrieves the current price of CYBRO tokens
     * @return The current CYBRO token price
     * @dev Reverts if the price has not been set or is incorrectly set to 0
     */
    function getPrice() external view returns (uint256) {
        if (_price == 0) revert IncorrectPrice();
        return _price;
    }
}
