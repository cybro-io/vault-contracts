// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library IMultiRewarder {
    struct RewardDetails {
        uint256 rewardPerSec;
        uint160 totalAllocPoints;
        uint48 start;
        uint48 end;
        bool exists;
    }
}

interface IStargateMultiRewarder {
    error MultiRewarderDisconnectedStakingToken(address token);
    error MultiRewarderIncorrectNative(uint256 expected, uint256 actual);
    error MultiRewarderMaxActiveRewardTokens();
    error MultiRewarderMaxPoolsForRewardToken();
    error MultiRewarderNativeTransferFailed(address to, uint256 amount);
    error MultiRewarderPoolFinished(address rewardToken);
    error MultiRewarderRenounceOwnershipDisabled();
    error MultiRewarderStartInPast(uint256 start);
    error MultiRewarderUnauthorizedCaller(address caller);
    error MultiRewarderUnregisteredToken(address token);
    error MultiRewarderZeroDuration();
    error MultiRewarderZeroRewardRate();
    error RewarderAlreadyConnected(address stakingToken);

    event AllocPointsSet(address indexed rewardToken, address[] indexed stakeToken, uint48[] allocPoint);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PoolRegistered(address indexed rewardToken, address indexed stakeToken);
    event RewardExtended(address indexed rewardToken, uint256 amountAdded, uint48 newEnd);
    event RewardRegistered(address indexed rewardToken);
    event RewardSet(
        address indexed rewardToken, uint256 amountAdded, uint256 amountPeriod, uint48 start, uint48 duration
    );
    event RewardStopped(address indexed rewardToken, address indexed receiver, bool pullTokens);
    event RewarderConnected(address indexed stakingToken);
    event RewardsClaimed(address indexed user, address[] rewardTokens, uint256[] amounts);

    function allocPointsByReward(address rewardToken) external view returns (address[] memory, uint48[] memory);
    function allocPointsByStake(address stakingToken) external view returns (address[] memory, uint48[] memory);
    function connect(address stakingToken) external;
    function extendReward(address rewardToken, uint256 amount) external payable;
    function getRewards(address stakingToken, address user)
        external
        view
        returns (address[] memory, uint256[] memory);
    function onUpdate(address stakingToken, address user, uint256 oldStake, uint256 oldSupply, uint256) external;
    function owner() external view returns (address);
    function renounceOwnership() external view;
    function rewardDetails(address rewardToken) external view returns (IMultiRewarder.RewardDetails memory);
    function rewardTokens() external view returns (address[] memory);
    function setAllocPoints(address rewardToken, address[] memory stakingTokens, uint48[] memory allocPoints)
        external;
    function setReward(address rewardToken, uint256 amount, uint48 start, uint48 duration) external payable;
    function staking() external view returns (address);
    function stopReward(address rewardToken, address receiver, bool pullTokens) external;
    function transferOwnership(address newOwner) external;
}
