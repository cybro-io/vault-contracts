// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IStargateStaking {
    error InvalidCaller();
    error InvalidReceiver(address receiver);
    error NonExistentPool(address token);
    error StargateStakingRenounceOwnershipDisabled();
    error WithdrawalAmountExceedsBalance();

    event Deposit(address indexed token, address indexed from, address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PoolSet(address indexed token, address rewarder, bool exists);
    event Withdraw(address indexed token, address indexed from, address indexed to, uint256 amount, bool withUpdate);

    function balanceOf(address token, address user) external view returns (uint256);
    function claim(address[] memory lpTokens) external;
    function deposit(address token, uint256 amount) external;
    function depositTo(address token, address to, uint256 amount) external;
    function emergencyWithdraw(address token) external;
    function isPool(address token) external view returns (bool);
    function owner() external view returns (address);
    function renounceOwnership() external view;
    function rewarder(address token) external view returns (address);
    function setPool(address token, address newRewarder) external;
    function tokens(uint256 start, uint256 end) external view returns (address[] memory);
    function tokens() external view returns (address[] memory);
    function tokensLength() external view returns (uint256);
    function totalSupply(address token) external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function withdraw(address token, uint256 amount) external;
    function withdrawToAndCall(address token, address to, uint256 amount, bytes memory data) external;
}
