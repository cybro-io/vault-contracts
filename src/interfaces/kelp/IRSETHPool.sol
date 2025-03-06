// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IRSETHPool {
    error AlreadySupportedToken();
    error ContractNotPaused();
    error ContractPaused();
    error DeprecatedFunction();
    error EthDepositDisabled();
    error InsufficientETHBalance();
    error InsufficientNativeFee();
    error InvalidAmount();
    error InvalidLzChainId();
    error InvalidMinAmount();
    error InvalidSlippageTolerance();
    error TokenNotFoundError();
    error TransferFailed();
    error UnsupportedOracle();
    error UnsupportedToken();
    error ZeroAddressNotAllowed();

    event AddSupportedToken(address token);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event AssetsMovedForBridging(uint256 ethBalanceMinusFees);
    event AssetsMovedForBridging(uint256 tokenBalanceMinusFees, address token);
    event BridgedETHToL1(uint32 lzChainId, address l1Receiver, uint256 amountSent, uint256 amountReceived);
    event FeeBpsSet(uint256 feeBps);
    event FeesWithdrawn(uint256 feeEarnedInETH);
    event FeesWithdrawn(uint256 feeEarnedInETH, address token);
    event Initialized(uint8 version);
    event IsEthDepositEnabled(bool isEthDepositEnabled);
    event L1VaultETHForL2ChainSet(address l1VaultETHForL2Chain);
    event LzChainIdSet(uint32 lzChainId);
    event OracleSet(address oracle);
    event Paused(address account);
    event RemovedSupportedToken(address token);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event StargatePoolSet(address stargatePool);
    event SwapOccurred(address indexed user, uint256 rsETHAmount, uint256 fee, string referralId);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Unpaused(address account);

    function BRIDGER_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function LEGACY_MANAGER_ROLE() external view returns (bytes32);
    function TIMELOCK_ROLE() external view returns (bytes32);
    function addSupportedToken(address token, address oracle) external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function bridgeAssets(uint256 amount, uint256 minAmount, uint256 nativeFee) external payable;
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function deposit(string memory referralId) external payable;
    function deposit(address token, uint256 amount, string memory referralId) external;
    function dstLzChainId() external view returns (uint32);
    function feeBps() external view returns (uint256);
    function feeEarnedInETH() external view returns (uint256);
    function feeEarnedInToken(address token) external view returns (uint256 feeEarned);
    function getETHBalanceMinusFees() external view returns (uint256);
    function getMinAmount(uint256 amount, uint256 slippageTolerance) external pure returns (uint256);
    function getNativeFee(uint256 amount, uint256 minAmount) external view returns (uint256);
    function getRate() external view returns (uint256);
    function getReceiver() external view returns (bytes32);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getSupportedTokens() external view returns (address[] memory);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function initialize(
        address admin,
        address manager,
        address _rsETH,
        address _wstETH,
        uint256 _feeBps,
        address _rsETHOracle,
        address _wstETH_ETHOracle
    ) external;
    function isEthDepositEnabled() external view returns (bool);
    function l1VaultETHForL2Chain() external view returns (address);
    function latestTxReceipt() external view returns (bytes32 guid, uint256 amountReceivedLD);
    function legacyFeeEarnedInWstETH() external view returns (uint256);
    function legacyWstETH() external view returns (address);
    function legacyWstETH_ETHOracle() external view returns (address);
    function moveAssetsForBridging() external view;
    function moveAssetsForBridging(address token) external;
    function name() external view returns (string memory);
    function pause() external;
    function paused() external view returns (bool);
    function reinitialize(address _l1VaultETHForL2Chain, address _stargatePool, uint32 _dstLzChainId) external;
    function reinitialize(uint32 _dstLzChainId) external;
    function removeSupportedToken(address token, uint256 tokenIndex) external;
    function renounceRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function rsETHOracle() external view returns (address);
    function setDstLzChainId(uint32 _dstLzChainId) external;
    function setFeeBps(uint256 _feeBps) external;
    function setIsEthDepositEnabled(bool _isEthDepositEnabled) external;
    function setL1VaultETHForL2Chain(address _l1VaultETHForL2Chain) external;
    function setRSETHOracle(address _rsETHOracle) external;
    function setStargatePool(address _stargatePool) external;
    function stargatePool() external view returns (address);
    function supportedTokenList(uint256) external view returns (address);
    function supportedTokenOracle(address token) external view returns (address oracle);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function unpause() external;
    function viewSwapRsETHAmountAndFee(uint256 amount, address token)
        external
        view
        returns (uint256 rsETHAmount, uint256 fee);
    function viewSwapRsETHAmountAndFee(uint256 amount) external view returns (uint256 rsETHAmount, uint256 fee);
    function withdrawFees(address receiver) external;
    function withdrawFees(address receiver, address token) external;
    function wrsETH() external view returns (address);
}
