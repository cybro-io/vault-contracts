// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library IManager {
    struct ExistingRange {
        uint256 index;
        bool burn;
        uint128 liquidityToBurn;
        bool remove;
        uint256 amount0;
        uint256 amount1;
    }

    struct NewRange {
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0;
        uint256 amount1;
    }

    struct Range {
        int24 tickLower;
        int24 tickUpper;
    }

    struct Swap {
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 minAmountOut;
        bytes externalData;
    }
}

interface IAlgebraLPManager {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event ExistingRangesRebalance(IManager.ExistingRange[]);
    event GovernorUpdated(address _oldGovernor, address _newGovernor);
    event KeeperAdded(address _newKeeper);
    event KeeperRemoved(address _operator);
    event NewRangesRebalance(IManager.NewRange[]);
    event OperatorAdded(address _newOperator);
    event OperatorRemoved(address _operator);
    event Position(uint256 amount0, uint256 amount1);
    event Retention(
        address indexed receiver,
        uint256 amount0AfterRetention,
        uint256 amount1AfterRetention,
        uint256 retention0,
        uint256 retention1,
        string typeOf
    );
    event Rewards(uint256 rewards0, uint256 rewards1);
    event RewardsPerRange(IManager.Range indexed, uint256 rewards0, uint256 rewards1);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function GOVERNOR() external view returns (bytes32);
    function KEEPER() external view returns (bytes32);
    function OPERATOR() external view returns (bytes32);
    function addKeeper(address _newKeeper) external;
    function addOperator(address _newOperator) external;
    function algebraMintCallback(uint256 amount0, uint256 amount1, bytes memory data) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function aum() external returns (uint256 amount0, uint256 amount1);
    function aumWithoutCollect() external view returns (uint256 amount0, uint256 amount1);
    function balanceOf(address account) external view returns (uint256);
    function burn(address from, uint256 amount) external;
    function burnLiquidity(uint128 _liquidity, uint256 _index, bool _notional)
        external
        returns (uint256 amount0, uint256 amount1);
    function chargeWithdrawalRate() external view returns (bool);
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function defaultRange() external view returns (int24, int24);
    function emergencyTransfer(address _to, address _asset) external;
    function getPool() external view returns (address);
    function getRanges() external view returns (IManager.Range[] memory);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function govApproval(address _token, address _spender, uint256 _amount) external;
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function incentiveReceiver() external view returns (address);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function initializeLPManager(
        address _pool,
        address _receiver,
        address _price,
        address _swapper,
        address _incentiveReceiver,
        uint256 _yieldRate,
        uint256 _withdrawalRate,
        string memory _name,
        string memory _symbol,
        int24 defaultLower,
        int24 defaultUpper
    ) external;
    function lpPosition(int24 tickLower, int24 tickUpper)
        external
        view
        returns (uint128 liquidity, uint128 rewards0, uint128 rewards1);
    function mint(address to, uint256 amount) external;
    function mintLiquidity(address _user, uint256 _index, uint256 _amount0, uint256 _amount1)
        external
        returns (uint256, uint256);
    function name() external view returns (string memory);
    function rebalance(
        IManager.Swap memory _swap,
        IManager.ExistingRange[] memory _existingRanges,
        IManager.NewRange[] memory _newRange
    ) external;
    function redeemLiquidity(uint256 _position, address _receiver)
        external
        returns (uint256 amount0, uint256 amount1, uint256 amount0AfterRetention, uint256 amount1AfterRetention);
    function removeKeeper(address _operator) external;
    function removeOperator(address _operator) external;
    function renounceRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function setIncentives(
        address _gaugeReceiver,
        address _incentiveReceiver,
        uint256 _yieldRate,
        uint256 _withdrawalRate
    ) external;
    function setInternalContracts(address _receiver, address _price, address _swapper) external;
    function swapDefaultRange(uint256 _index) external;
    function symbol() external view returns (string memory);
    function toggleWithdrawalRate() external;
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferAssets(address from, uint256 amount0, uint256 amount1) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function updateGovernor(address _newGovernor) external;
    function withdrawalRate() external view returns (uint256);
    function yieldRate() external view returns (uint256);
}
