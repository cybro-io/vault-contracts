// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library LRewardTracker {
    struct Swap {
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 minAmountOut;
        bytes externalData;
    }
}

interface IRewardTracker {
    event Claim0(address indexed receiver, uint256 amount);
    event Claim1(address indexed receiver, uint256 amount);
    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);
    event GovernorUpdated(address _oldGovernor, address _newGovernor);
    event KeeperAdded(address _newKeeper);
    event KeeperRemoved(address _operator);
    event MerkleClaim(address[] users, address[] tokens, uint256[] amounts);
    event OperatorAdded(address _newOperator);
    event OperatorRemoved(address _operator);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Stake(address indexed depositor, uint256 amount);
    event UpdateRewards0(address indexed _account, uint256 _rewards, uint256 _totalShares, uint256 _rewardPerShare);
    event UpdateRewards1(address indexed _account, uint256 _rewards, uint256 _totalShares, uint256 _rewardPerShare);
    event Withdraw(address indexed _account, uint256 _amount);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function GOVERNOR() external view returns (bytes32);
    function KEEPER() external view returns (bytes32);
    function OPERATOR() external view returns (bytes32);
    function PRECISION() external view returns (uint256);
    function USDB() external view returns (address);
    function WETH() external view returns (address);
    function addKeeper(address _newKeeper) external;
    function addOperator(address _newOperator) external;
    function blastID() external view returns (uint256);
    function claim(address _account) external returns (uint256, uint256);
    function claim(address[] memory users, address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs)
        external;
    function claimAllYield() external;
    function claimIncentives(address _token) external;
    function claimable(address _account) external view returns (uint256 claimable0, uint256 claimable1);
    function claimableReward0(address) external view returns (uint256);
    function claimableReward1(address) external view returns (uint256);
    function cumulativeRewardPerShare0() external view returns (uint256);
    function cumulativeRewardPerShare1() external view returns (uint256);
    function cumulativeRewards0(address) external view returns (uint256);
    function cumulativeRewards1(address) external view returns (uint256);
    function depositRewards(uint256 _rewards0, uint256 _rewards1) external;
    function emergencyWithdrawal(address _to, address[] memory _assets, bool _withdrawNative) external;
    function externalIncentives() external view returns (address);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function govApproval(address _token, address _spender, uint256 _amount) external;
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function incentiveReceiver() external view returns (address);
    function initializeDoubleTracker(
        address _manager,
        address _swapper,
        address _receiver,
        address _distributor,
        address _incentiveReceiver
    ) external;
    function manager() external view returns (address);
    function merkleDistributor() external view returns (address);
    function previousCumulatedRewardPerShare0(address) external view returns (uint256);
    function previousCumulatedRewardPerShare1(address) external view returns (uint256);
    function receiver() external view returns (address);
    function removeKeeper(address _operator) external;
    function removeOperator(address _operator) external;
    function renounceRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function rewardToken0() external view returns (address);
    function rewardToken1() external view returns (address);
    function setExternalIncentives(address _externalIncentives) external;
    function setIncentiveReceiver(address _incentiveReceiver) external;
    function setInternalContracts(address _swapper, address _receiver, address _distributor) external;
    function setManager(address _manager) external;
    function stake(address _account, uint256 _amount) external returns (uint256);
    function stakedAmount(address _account) external view returns (uint256);
    function stakedAmounts(address) external view returns (uint256);
    function swapAndProcess(LRewardTracker.Swap[] memory _swap) external;
    function swapper() external view returns (address);
    function toggleOnlyOperatorCanClaimDistributor() external;
    function toggleOperatorDistributor(address operator) external;
    function totalStakedAmount() external view returns (uint256);
    function updateGovernor(address _newGovernor) external;
    function updateRate(uint256 _newRate) external;
    function updateRewards() external;
    function withdraw(address _account, uint256 _amount) external returns (uint256);
    function yieldRate() external view returns (uint256);
}
