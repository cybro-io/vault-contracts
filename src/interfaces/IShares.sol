//SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

interface IShares {
    function pending() external view returns (uint256);
    function addValue(uint256 value) external;
    function count() external view returns (uint256);
}
