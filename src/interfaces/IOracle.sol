// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

interface IOracle {
    function updatePrice(uint256 price) external;
    function getPrice() external view returns (uint256);
    function cybro() external view returns (address);
    function usdb() external view returns (address);
}
