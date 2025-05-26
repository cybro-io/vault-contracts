// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";

library OracleData {
    /// @notice The threshold for stale prices
    uint256 public constant PRICE_STALE_THRESHOLD = 1 hours;

    /// @notice Error thrown when a price is stale
    error StalePrice();

    /// @notice Error thrown when a round is not complete
    error RoundNotComplete();

    /// @notice Error thrown when a chainlink price is reporting 0
    error ChainlinkPriceReportingZero();

    /**
     * @notice Internal function to get the price from the oracle
     * @param oracle The oracle to get the price from
     * @return The price
     */
    function getPrice(IChainlinkOracle oracle) public view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = oracle.latestRoundData();

        require(updatedAt != 0, RoundNotComplete());
        require(block.timestamp - updatedAt <= PRICE_STALE_THRESHOLD, StalePrice());
        require(price > 0, ChainlinkPriceReportingZero());

        return uint256(price);
    }
}
