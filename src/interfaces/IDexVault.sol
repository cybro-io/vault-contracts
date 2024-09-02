// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

interface IDexVault {
    function getPositionAmounts() external view returns (uint256 amount0, uint256 amount1);
    function getCurrentPrice() external view returns (uint160);
    function getCurrentSqrtPrice() external view returns (uint160);

    function deposit(bool inToken0, uint256 amount, address receiver, uint160, uint160)
        external
        returns (uint256 shares);

    function redeem(bool inToken0, uint256 shares, address receiver, address owner, uint256 minAmountOut)
        external
        returns (uint256 assets);

    function withdrawFunds(address token) external;
}
