// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IVault is IERC20Metadata {
    function pause() external;
    function unpause() external;
    function totalAssets() external view returns (uint256);
    function sharePrice() external view returns (uint256);
    function deposit(uint256 assets, address receiver, uint256 minShares) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner, uint256 minAssets)
        external
        returns (uint256 assets);
    function withdrawFunds(address token) external;
}
