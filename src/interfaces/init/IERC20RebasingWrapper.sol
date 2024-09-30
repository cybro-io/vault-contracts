// SPDX-License-Identifier: None
pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IERC20RebasingWrapper is IERC20Metadata {
    /// @dev wrap underlying token to wrapped token
    /// @param _amt amount of underlying token to wrap
    /// @return shares amount of shares minted
    function wrap(uint256 _amt) external returns (uint256 shares);

    /// @dev unwrap wrapped token to underlying token
    /// @param _shares amount of wrapped token to unwrap
    /// @return amt amount of underlying token received
    function unwrap(uint256 _shares) external returns (uint256 amt);

    /// @dev claim pending interests from underlying token
    function accrueYield() external;

    /// @dev blast-erc20-rebasing token address
    function underlyingToken() external view returns (address);

    /// @notice no need to accruing interests since claimable amount is already included in totalAssets
    /// @dev convert amount of underlying token to shares
    function toShares(uint256 _amt) external view returns (uint256);

    /// @dev convert amount of underlying token to shares
    function toShares(uint256 _amt, Math.Rounding _rounding) external view returns (uint256);

    /// @notice no need to accruing interests since claimable amount is already included in totalAssets
    /// @dev convert amount of shares to underlying token
    function toAmt(uint256 _shares) external view returns (uint256);

    /// @dev convert amount of shares to underlying token
    function toAmt(uint256 _shares, Math.Rounding _rounding) external view returns (uint256);

    /// @notice no need to accruing interests since claimable amount is already included in totalAssets
    /// @dev total
    function totalAssets() external view returns (uint256);
}
