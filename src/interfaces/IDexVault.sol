// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

interface IDexVault {
    /// @param inToken0 Indicates whether the input token is token0 (true) or token1 (false)
    /// @param amount The amount of the input token to deposit
    /// @param receiver The address that will receive the vault shares
    /// @param minSqrtPriceX96 The minimum price threshold for the swap
    /// @param maxSqrtPriceX96 The maximum price threshold for the swap
    struct DepositInput {
        bool inToken0;
        uint256 amount;
        address receiver;
        uint160 minSqrtPriceX96;
        uint160 maxSqrtPriceX96;
    }

    function getPositionAmounts() external view returns (uint256 amount0, uint256 amount1);
    function getCurrentSqrtPrice() external view returns (uint160);

    function deposit(DepositInput memory input) external returns (uint256 shares);

    function redeem(bool inToken0, uint256 shares, address receiver, address owner, uint256 minAmountOut)
        external
        returns (uint256 assets);

    function withdrawFunds(address token) external;
}
