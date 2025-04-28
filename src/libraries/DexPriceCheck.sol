// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.29;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";
import {IAlgebraPool as IAlgebraPoolV1_9} from "../interfaces/algebra/IAlgebraPoolV1_9.sol";
import {IAlgebraPool} from "../interfaces/algebra/IAlgebraPool.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IAlgebraBasePluginV1} from "../interfaces/algebra/IAlgebraBasePluginV1.sol";

/**
 * @title DexPriceCheck
 * @notice Library for checking if the price of a Dex pool is being manipulated
 */
library DexPriceCheck {
    /* ========== ERRORS ========== */

    error PriceManipulation();
    error StalePrice();
    error RoundNotComplete();
    error ChainlinkPriceReportingZero();

    /* ========== CONSTANTS ========== */

    /// @notice Precision for deviation
    uint32 public constant deviationPrecision = 10000;

    /// @notice Maximum deviation
    uint32 public constant maxDeviation = 200;

    /**
     * @notice Function to check if the price of the Dex pool is being manipulated
     * @param oracleToken0_ The address of the first token oracle
     * @param oracleToken1_ The address of the second token oracle
     * @param token0_ The address of the first token
     * @param token1_ The address of the second token
     * @param isAlgebra Whether the pool is an Algebra pool
     * @param pool The address of the pool
     * @param currentSqrtPrice The current square root price of the pool
     */
    function checkPriceManipulation(
        IChainlinkOracle oracleToken0_,
        IChainlinkOracle oracleToken1_,
        address token0_,
        address token1_,
        bool isAlgebra,
        address pool,
        uint256 currentSqrtPrice
    ) public view {
        uint256 trustedSqrtPrice;
        if (address(oracleToken0_) == address(0)) {
            trustedSqrtPrice = getTwap(pool, isAlgebra);
        } else {
            trustedSqrtPrice = getSqrtPriceFromOracles(oracleToken0_, oracleToken1_, token0_, token1_);
        }
        uint256 deviation = (currentSqrtPrice ** 2) * deviationPrecision / (trustedSqrtPrice ** 2);
        require(
            (deviation > deviationPrecision - maxDeviation) && (deviation < deviationPrecision + maxDeviation),
            PriceManipulation()
        );
    }

    /**
     * @dev Calculates the square root of the price ratio between two tokens based on data from oracle.
     * @param oracleToken0_ The address of the first token oracle
     * @param oracleToken1_ The address of the second token oracle
     * @param token0_ The address of the first token
     * @param token1_ The address of the second token
     * @return The square root price
     */
    function getSqrtPriceFromOracles(
        IChainlinkOracle oracleToken0_,
        IChainlinkOracle oracleToken1_,
        address token0_,
        address token1_
    ) public view returns (uint256) {
        uint256 price0 = _getPrice(oracleToken0_);
        uint256 price1 = _getPrice(oracleToken1_);
        uint8 decimals0 = oracleToken0_.decimals();
        uint8 decimals1 = oracleToken1_.decimals();
        if (decimals0 > decimals1) {
            price1 = price1 * (10 ** (decimals0 - decimals1));
        } else if (decimals1 > decimals0) {
            price0 = price0 * (10 ** (decimals1 - decimals0));
        }
        return Math.sqrt(Math.mulDiv(price0, 2 ** 96, price1))
            * Math.sqrt(
                Math.mulDiv(10 ** IERC20Metadata(token1_).decimals(), 2 ** 96, 10 ** IERC20Metadata(token0_).decimals())
            );
    }

    /**
     * @notice Calculates the TWAP (Time-Weighted Average Price) of the Dex pool
     * @dev This function calculates the average price of the Dex pool over a last 30 minutes
     * @param pool The address of the pool
     * @param isAlgebra Whether the pool is an Algebra pool
     * @return The TWAP of the Dex pool
     */
    function getTwap(address pool, bool isAlgebra) public view returns (uint256) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 0;
        secondsAgos[1] = 1800;

        (int56[] memory tickCumulatives) = _observe(secondsAgos, pool, isAlgebra);
        int56 tickCumulativeDelta = tickCumulatives[0] - tickCumulatives[1];
        int56 timeElapsed = int56(uint56(secondsAgos[1]));

        int24 averageTick = int24(tickCumulativeDelta / timeElapsed);
        if (tickCumulativeDelta < 0 && (tickCumulativeDelta % timeElapsed != 0)) {
            averageTick--;
        }

        return uint256(TickMath.getSqrtRatioAtTick(averageTick));
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Abstract function to observe the price of the Dex pool
     * @param secondsAgos The time periods to observe the price
     * @param pool The address of the pool
     * @param isAlgebra Whether the pool is an Algebra pool
     * @return tickCumulatives The observed tick cumulative
     */
    function _observe(uint32[] memory secondsAgos, address pool, bool isAlgebra)
        internal
        view
        returns (int56[] memory tickCumulatives)
    {
        if (isAlgebra) {
            (bool success, bytes memory data) =
                address(pool).staticcall(abi.encodeWithSelector(IAlgebraPoolV1_9.getTimepoints.selector, secondsAgos));
            if (success) {
                (tickCumulatives,,,) = abi.decode(data, (int56[], uint160[], uint112[], uint256[]));
            } else {
                (tickCumulatives,) = IAlgebraBasePluginV1(IAlgebraPool(pool).plugin()).getTimepoints(secondsAgos);
            }
        } else {
            (tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);
        }
    }

    /**
     * @notice Internal function to get the price from the oracle
     * @param oracle The oracle to get the price from
     * @return The price
     */
    function _getPrice(IChainlinkOracle oracle) internal view returns (uint256) {
        (uint80 roundID, int256 price,, uint256 timestamp, uint80 answeredInRound) = oracle.latestRoundData();

        require(answeredInRound >= roundID, StalePrice());
        require(timestamp > 0, RoundNotComplete());
        require(price > 0, ChainlinkPriceReportingZero());

        return uint256(price);
    }
}
