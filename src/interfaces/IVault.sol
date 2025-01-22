// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFeeProvider} from "./IFeeProvider.sol";

interface IVault is IERC20Metadata {
    /// @notice Error thrown when attempting to withdraw an invalid token
    error InvalidTokenToWithdraw(address token);

    function pause() external;
    function unpause() external;
    function asset() external view returns (address);
    function feeProvider() external view returns (IFeeProvider);
    function feeRecipient() external view returns (address);
    function feePrecision() external view returns (uint32);
    function totalAssets() external view returns (uint256);
    function sharePrice() external view returns (uint256);
    function deposit(uint256 assets, address receiver, uint256 minShares) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner, uint256 minAssets)
        external
        returns (uint256 assets);
    function quoteWithdrawalFee(address account) external view returns (uint256);
    function getWaterline(address account) external view returns (uint256);
    function getBalanceInUnderlying(address account) external view returns (uint256);
    function getProfit(address account) external view returns (uint256);
    function underlyingTVL() external view returns (uint256);
    function getDepositFee(address account) external view returns (uint32);
    function getWithdrawalFee(address account) external view returns (uint32);
    function getPerformanceFee(address account) external view returns (uint32);
    function collectPerformanceFee(address[] memory accounts) external;
    function getManagementFee() external view returns (uint32);
    function collectManagementFee() external;
    function getLastTimeManagementFeeCollected() external view returns (uint256);
    function emergencyWithdraw(address[] memory accounts) external;
    function withdrawFunds(address token) external;
}
