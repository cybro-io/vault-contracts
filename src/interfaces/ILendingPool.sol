// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface ILendingPool is IERC20Metadata {
    function deposit(uint256 assets, address receiver) external;
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function totalAssets() external view returns (uint256);
    function sharePrice() external view returns (uint256);
}
