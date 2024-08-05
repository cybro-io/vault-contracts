// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

interface IYieldStaking {
    struct StakingUser {
        uint256 balanceScaled;
        uint256 lockedBalance;
        uint256 remainders;
        uint256 timestampToWithdraw;
    }

    struct StakingInfo {
        uint256 totalSupplyScaled;
        uint256 lastIndex;
        mapping(address => StakingUser) users;
    }

    function userInfo(address targetToken, address user) external view returns (StakingUser memory);

    function lastIndex(address targetToken) external view returns (uint256);

    function totalSupply(address targetToken) external view returns (uint256);

    function balanceAndRewards(address targetToken, address account)
        external
        view
        returns (uint256 balance, uint256 rewards);

    function stake(address depositToken, uint256 amount) external payable;

    function claimReward(
        address targetToken,
        address rewardToken,
        uint256 rewardAmount,
        bool getETH,
        bytes memory signature,
        uint256 id
    ) external;

    function withdraw(address targetToken, uint256 amount, bool getETH) external;
}
