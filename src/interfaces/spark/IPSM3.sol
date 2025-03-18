// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IPSM3 {
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);

    event Deposit(
        address indexed asset,
        address indexed user,
        address indexed receiver,
        uint256 assetsDeposited,
        uint256 sharesMinted
    );
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PocketSet(address indexed oldPocket, address indexed newPocket, uint256 amountTransferred);
    event Swap(
        address indexed assetIn,
        address indexed assetOut,
        address sender,
        address indexed receiver,
        uint256 amountIn,
        uint256 amountOut,
        uint256 referralCode
    );
    event Withdraw(
        address indexed asset,
        address indexed user,
        address indexed receiver,
        uint256 assetsWithdrawn,
        uint256 sharesBurned
    );

    function convertToAssetValue(uint256 numShares) external view returns (uint256);
    function convertToAssets(address asset, uint256 numShares) external view returns (uint256);
    function convertToShares(address asset, uint256 assets) external view returns (uint256);
    function convertToShares(uint256 assetValue) external view returns (uint256);
    function deposit(address asset, address receiver, uint256 assetsToDeposit) external returns (uint256 newShares);
    function owner() external view returns (address);
    function pocket() external view returns (address);
    function previewDeposit(address asset, uint256 assetsToDeposit) external view returns (uint256);
    function previewSwapExactIn(address assetIn, address assetOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);
    function previewSwapExactOut(address assetIn, address assetOut, uint256 amountOut)
        external
        view
        returns (uint256 amountIn);
    function previewWithdraw(address asset, uint256 maxAssetsToWithdraw)
        external
        view
        returns (uint256 sharesToBurn, uint256 assetsWithdrawn);
    function rateProvider() external view returns (address);
    function renounceOwnership() external;
    function setPocket(address newPocket) external;
    function shares(address user) external view returns (uint256 shares);
    function susds() external view returns (address);
    function swapExactIn(
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address receiver,
        uint256 referralCode
    ) external returns (uint256 amountOut);
    function swapExactOut(
        address assetIn,
        address assetOut,
        uint256 amountOut,
        uint256 maxAmountIn,
        address receiver,
        uint256 referralCode
    ) external returns (uint256 amountIn);
    function totalAssets() external view returns (uint256);
    function totalShares() external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function usdc() external view returns (address);
    function usds() external view returns (address);
    function withdraw(address asset, address receiver, uint256 maxAssetsToWithdraw)
        external
        returns (uint256 assetsWithdrawn);
}
