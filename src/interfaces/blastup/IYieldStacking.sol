// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IYieldStaking {
    struct StakingUser {
        uint256 balanceScaled;
        uint256 lockedBalance;
        uint256 remainders;
        uint256 timestampToWithdraw;
    }

    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error FailedInnerCall();
    error InvalidInitialization();
    error InvalidPool(address token);
    error NotInitializing();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error SafeERC20FailedOperation(address token);

    event Initialized(uint64 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RewardClaimed(address stakingToken, address indexed user, address rewardToken, uint256 amountInStakingToken);
    event Staked(address stakingToken, address indexed user, uint256 amount);
    event Withdrawn(address stakingToken, address indexed user, uint256 amount);

    receive() external payable;

    function USDB() external view returns (address);
    function WETH() external view returns (address);
    function balanceAndRewards(address targetToken, address account)
        external
        view
        returns (uint256 balance, uint256 rewards);
    function claimReward(
        address targetToken,
        address rewardToken,
        uint256 rewardAmount,
        bool getETH,
        bytes memory signature,
        uint256 id
    ) external;
    function decimalsUSDB() external view returns (uint8);
    function initialize(address _owner, address _points, address _pointsOperator) external;
    function lastIndex(address targetToken) external view returns (uint256);
    function launchpad() external view returns (address);
    function minTimeToWithdraw() external view returns (uint256);
    function minUSDBStakeValue() external view returns (uint256);
    function oracle() external view returns (address);
    function oracleDecimals() external view returns (uint8);
    function owner() external view returns (address);
    function renounceOwnership() external;
    function setMinTimeToWithdraw(uint256 _minTimeToWithdraw) external;
    function setMinUSDBStakeValue(uint256 _minUSDBStakeValue) external;
    function stake(address depositToken, uint256 amount) external payable;
    function stakingInfos(address) external view returns (uint256 totalSupplyScaled, uint256 lastIndex);
    function totalSupply(address targetToken) external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function userInfo(address targetToken, address user) external view returns (StakingUser memory);
    function withdraw(address targetToken, uint256 amount, bool getETH) external;
}
