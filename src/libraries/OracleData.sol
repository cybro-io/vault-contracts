// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";

library OracleData {
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
        require(price > 0, ChainlinkPriceReportingZero());

        return uint256(price);
    }
}
