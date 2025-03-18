// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IAcceleratingDistributor {
    struct UserDeposit {
        uint256 cumulativeBalance;
        uint256 averageDepositTime;
        uint256 rewardsAccumulatedPerToken;
        uint256 rewardsOutstanding;
    }

    event Exit(address indexed token, address indexed user, uint256 tokenCumulativeStaked);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RecoverToken(address indexed token, uint256 amount);
    event RewardsWithdrawn(
        address indexed token,
        address indexed user,
        uint256 rewardsToSend,
        uint256 tokenLastUpdateTime,
        uint256 tokenRewardPerTokenStored,
        uint256 userRewardsOutstanding,
        uint256 userRewardsPaidPerToken
    );
    event Stake(
        address indexed token,
        address indexed user,
        uint256 amount,
        uint256 averageDepositTime,
        uint256 cumulativeBalance,
        uint256 tokenCumulativeStaked
    );
    event TokenConfiguredForStaking(
        address indexed token,
        bool enabled,
        uint256 baseEmissionRate,
        uint256 maxMultiplier,
        uint256 secondsToMaxMultiplier,
        uint256 lastUpdateTime
    );
    event Unstake(
        address indexed token,
        address indexed user,
        uint256 amount,
        uint256 remainingCumulativeBalance,
        uint256 tokenCumulativeStaked
    );

    function baseRewardPerToken(address stakedToken) external view returns (uint256);
    function configureStakingToken(
        address stakedToken,
        bool enabled,
        uint256 baseEmissionRate,
        uint256 maxMultiplier,
        uint256 secondsToMaxMultiplier
    ) external;
    function exit(address stakedToken) external;
    function getAverageDepositTimePostDeposit(address stakedToken, address account, uint256 amount)
        external
        view
        returns (uint256);
    function getCumulativeStaked(address stakedToken) external view returns (uint256);
    function getCurrentTime() external view returns (uint256);
    function getOutstandingRewards(address stakedToken, address account) external view returns (uint256);
    function getTimeSinceAverageDeposit(address stakedToken, address account) external view returns (uint256);
    function getUserRewardMultiplier(address stakedToken, address account) external view returns (uint256);
    function getUserStake(address stakedToken, address account) external view returns (UserDeposit memory);
    function multicall(bytes[] memory data) external returns (bytes[] memory results);
    function owner() external view returns (address);
    function recoverToken(address token) external;
    function renounceOwnership() external;
    function rewardToken() external view returns (address);
    function stake(address stakedToken, uint256 amount) external;
    function stakeFor(address stakedToken, uint256 amount, address beneficiary) external;
    function stakingTokens(address)
        external
        view
        returns (
            bool enabled,
            uint256 baseEmissionRate,
            uint256 maxMultiplier,
            uint256 secondsToMaxMultiplier,
            uint256 cumulativeStaked,
            uint256 rewardPerTokenStored,
            uint256 lastUpdateTime
        );
    function transferOwnership(address newOwner) external;
    function unstake(address stakedToken, uint256 amount) external;
    function withdrawReward(address stakedToken) external;
}
