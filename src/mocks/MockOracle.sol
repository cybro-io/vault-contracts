// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";

contract MockOracle {
    IChainlinkOracle public immutable oracle;

    constructor(IChainlinkOracle oracle_) {
        oracle = oracle_;
    }

    function decimals() external view returns (uint8) {
        return oracle.decimals();
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        (uint80 roundId, int256 answer, uint256 startedAt,, uint80 answeredInRound) = oracle.latestRoundData();
        return (roundId, answer, startedAt, block.timestamp - 1, answeredInRound);
    }
}
