//SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

interface IShares {
    function pending() external view returns (uint256);
    function addValue(uint256 value) external;
    function count() external view returns (uint256);
}
