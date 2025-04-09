// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library LRouter {
    struct DepositInput {
        uint256 amount0;
        uint256 amount1;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 minPosition;
        uint256 minShares;
        address receiver;
        bool compound;
        uint8 rewardOption;
    }

    struct ExecuteOrder {
        address user;
        uint256[] blockNumbers;
        uint256[] minAmount0;
        uint256[] minAmount1;
    }

    struct ExitOrder {
        address receiver;
        uint256 blockNumber;
        uint256 amount;
        uint256 price;
        bool compound;
        uint8 rewardOption;
        uint256 stage;
    }
}

interface IRouter {
    event Claim(address indexed caller, uint256 rewards0, uint256 rewards1, address indexed target, uint8 rewardOption);
    event Compound(address indexed caller, uint256 amount, uint256 shares, uint8 _rewardOption);
    event CompoundDeposit(address indexed caller, uint256 amount0, uint256 amount1, uint256 position);
    event Deposit(
        address indexed caller,
        address indexed receiver,
        uint256 amount0,
        uint256 amount1,
        uint256 position,
        uint256 shares,
        uint8 rewardOption
    );
    event GovernorUpdated(address _oldGovernor, address _newGovernor);
    event KeeperAdded(address _newKeeper);
    event KeeperRemoved(address _operator);
    event NewExitOrder(address indexed user, LRouter.ExitOrder order);
    event OperatorAdded(address _newOperator);
    event OperatorRemoved(address _operator);
    event OrderExecuted(
        address indexed user,
        uint256 blockNumber,
        uint256 price0,
        uint256 position,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );
    event OrderRemoved(address indexed user, LRouter.ExitOrder order);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event UnCompound(address indexed caller, uint256 shares, uint256 position, uint8 _rewardOption);
    event UpdateOrder(address indexed user, uint256 blockNumber, LRouter.ExitOrder order);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        uint256 shares,
        uint256 position,
        uint256 amount0,
        uint256 amount1,
        uint256 amount0AfterRetention,
        uint256 amount1AfterRetention,
        uint8 rewardOption
    );

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function GOVERNOR() external view returns (bytes32);
    function KEEPER() external view returns (bytes32);
    function OPERATOR() external view returns (bytes32);
    function addKeeper(address _newKeeper) external;
    function addOperator(address _newOperator) external;
    function claim(address _receiver, uint8 _rewardOption) external returns (uint256, uint256);
    function claimGas() external;
    function compound(uint256 _amount, uint8 _rewardOption) external returns (uint256);
    function compoundDeposit(uint256 _amount0, uint256 _amount1) external;
    function createExitOrder(address _receiver, uint256 _amount, uint256 _price, bool _compound, uint8 _rewardOption)
        external
        returns (uint256);
    function deposit(LRouter.DepositInput memory _deposit)
        external
        returns (uint256 amount0, uint256 amount1, uint256 position, uint256 shares);
    function emergencyTransfer(address _to, address _asset) external;
    function executeOrders(LRouter.ExecuteOrder[] memory _orders) external;
    function exitOrder(address, uint256)
        external
        view
        returns (
            address receiver,
            uint256 blockNumber,
            uint256 amount,
            uint256 price,
            bool compound,
            uint8 rewardOption,
            uint256 stage
        );
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function govApproval(address _token, address _spender, uint256 _amount) external;
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function initializeRouter(
        address _manager,
        address _price,
        address _compounder,
        address _tracker,
        address _trackerZero,
        address _trackerOne
    ) external;
    function previewPosition(
        uint256 price0,
        uint256 price1,
        uint256 amountIn0,
        uint256 amountIn1,
        uint256 position0,
        uint256 position1
    ) external view returns (uint256);
    function price() external view returns (address);
    function removeKeeper(address _operator) external;
    function removeOperator(address _operator) external;
    function removeOrder(uint256 _blockNumber) external;
    function renounceRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function unCompound(uint256 _shares, uint8 _rewardOption) external returns (uint256);
    function updateDeviation(uint256 _deviation) external;
    function updateGovernor(address _newGovernor) external;
    function updateInternalContracts(
        address _manager,
        address _price,
        address _compounder,
        address _tracker,
        address _trackerZero,
        address _trackerOne
    ) external;
    function updatePaused(bool _shouldPause) external;
    function withdraw(
        uint256 _position,
        address _receiver,
        uint256 _amount0Min,
        uint256 _amount1Min,
        bool _compound,
        uint8 _rewardOption
    ) external returns (uint256 amount0, uint256 amount1);
}
