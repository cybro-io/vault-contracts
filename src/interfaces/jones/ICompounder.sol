// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library LCompounder {
    struct Swap {
        address tokenIn;
        uint256 amountIn;
        address tokenOut;
        uint256 minAmountOut;
        bytes externalData;
    }
}

interface ICompounder {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Compound(uint256 amount0, uint256 amount1, uint256 totalAssets);
    event Deposit(address caller, address receiver, uint256 assets, uint256 shares);
    event GovernorUpdated(address _oldGovernor, address _newGovernor);
    event KeeperAdded(address _newKeeper);
    event KeeperRemoved(address _operator);
    event MerkleClaim(address[] users, address[] tokens, uint256[] amounts);
    event OperatorAdded(address _newOperator);
    event OperatorRemoved(address _operator);
    event Retention(
        address indexed receiver,
        uint256 amount0AfterRetention,
        uint256 amount1AfterRetention,
        uint256 retention0,
        uint256 retention1,
        string typeOf
    );
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Withdraw(address caller, address receiver, uint256, uint256 shares);

    function BLAST_YIELD_CONTRACT() external view returns (address);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function GOVERNOR() external view returns (bytes32);
    function KEEPER() external view returns (bytes32);
    function OPERATOR() external view returns (bytes32);
    function PRECISION() external view returns (uint256);
    function USDB() external view returns (address);
    function WETH() external view returns (address);
    function addKeeper(address _newKeeper) external;
    function addOperator(address _newOperator) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function blastID() external view returns (uint256);
    function claim(address[] memory users, address[] memory tokens, uint256[] memory amounts, bytes32[][] memory proofs)
        external;
    function claimAllYield() external;
    function claimGas() external;
    function compound() external;
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function deposit(uint256 _assets, address _receiver) external returns (uint256);
    function emergencyBurn(address _from, uint256 _shares) external;
    function emergencyTransfer(address _to, address _asset) external;
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
    function govApproval(address _token, address _spender, uint256 _amount) external;
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function incentiveReceiver() external view returns (address);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function initializeCompounder(
        address _router,
        address _tracker,
        address _manager,
        address _swapper,
        address _incentiveReceiver,
        uint256 _retentionPercentage,
        string memory _name,
        string memory _symbol
    ) external;
    function keeperSwap(LCompounder.Swap memory _swap) external;
    function manager() external view returns (address);
    function merkleDistributor() external view returns (address);
    function name() external view returns (string memory);
    function previewCompoundRetention(uint256 amount0, uint256 amount1)
        external
        view
        returns (uint256 amount0AfterRetention, uint256 amount1AfterRetention);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function redeem(uint256 _shares, address _receiver) external returns (uint256);
    function removeKeeper(address _operator) external;
    function removeOperator(address _operator) external;
    function renounceRole(bytes32 role, address account) external;
    function retentionPercentage() external view returns (uint256);
    function revokeRole(bytes32 role, address account) external;
    function router() external view returns (address);
    function setIncentives(address _incentiveReceiver, uint256 _retentionPercentage) external;
    function setInternalContracts(address _swapper, address _router, address _tracker) external;
    function setManager(address _manager) external;
    function setMerkl(address _distributor) external;
    function swapper() external view returns (address);
    function symbol() external view returns (string memory);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function tracker() external view returns (address);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function updateGovernor(address _newGovernor) external;
}
