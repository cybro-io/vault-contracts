// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IHubPool {
    event BondSet(address indexed newBondToken, uint256 newBondAmount);
    event CrossChainContractsSet(uint256 l2ChainId, address adapter, address spokePool);
    event EmergencyRootBundleDeleted(
        bytes32 indexed poolRebalanceRoot,
        bytes32 indexed relayerRefundRoot,
        bytes32 slowRelayRoot,
        address indexed proposer
    );
    event IdentifierSet(bytes32 newIdentifier);
    event L1TokenEnabledForLiquidityProvision(address l1Token, address lpToken);
    event L2TokenDisabledForLiquidityProvision(address l1Token, address lpToken);
    event LiquidityAdded(
        address indexed l1Token, uint256 amount, uint256 lpTokensMinted, address indexed liquidityProvider
    );
    event LiquidityRemoved(
        address indexed l1Token, uint256 amount, uint256 lpTokensBurnt, address indexed liquidityProvider
    );
    event LivenessSet(uint256 newLiveness);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(bool indexed isPaused);
    event ProposeRootBundle(
        uint32 challengePeriodEndTimestamp,
        uint8 poolRebalanceLeafCount,
        uint256[] bundleEvaluationBlockNumbers,
        bytes32 indexed poolRebalanceRoot,
        bytes32 indexed relayerRefundRoot,
        bytes32 slowRelayRoot,
        address indexed proposer
    );
    event ProtocolFeeCaptureSet(address indexed newProtocolFeeCaptureAddress, uint256 indexed newProtocolFeeCapturePct);
    event ProtocolFeesCapturedClaimed(address indexed l1Token, uint256 indexed accumulatedFees);
    event RootBundleCanceled(address indexed disputer, uint256 requestTime);
    event RootBundleDisputed(address indexed disputer, uint256 requestTime);
    event RootBundleExecuted(
        uint256 groupIndex,
        uint256 indexed leafId,
        uint256 indexed chainId,
        address[] l1Tokens,
        uint256[] bundleLpFees,
        int256[] netSendAmounts,
        int256[] runningBalances,
        address indexed caller
    );
    event SetEnableDepositRoute(
        uint256 indexed originChainId,
        uint256 indexed destinationChainId,
        address indexed originToken,
        bool depositsEnabled
    );
    event SetPoolRebalanceRoute(
        uint256 indexed destinationChainId, address indexed l1Token, address indexed destinationToken
    );
    event SpokePoolAdminFunctionTriggered(uint256 indexed chainId, bytes message);

    fallback() external payable;

    receive() external payable;

    function addLiquidity(address l1Token, uint256 l1TokenAmount) external payable;
    function bondAmount() external view returns (uint256);
    function bondToken() external view returns (address);
    function claimProtocolFeesCaptured(address l1Token) external;
    function crossChainContracts(uint256) external view returns (address adapter, address spokePool);
    function disableL1TokenForLiquidityProvision(address l1Token) external;
    function disputeRootBundle() external;
    function emergencyDeleteProposal() external;
    function enableL1TokenForLiquidityProvision(address l1Token) external;
    function exchangeRateCurrent(address l1Token) external returns (uint256);
    function executeRootBundle(
        uint256 chainId,
        uint256 groupIndex,
        uint256[] memory bundleLpFees,
        int256[] memory netSendAmounts,
        int256[] memory runningBalances,
        uint8 leafId,
        address[] memory l1Tokens,
        bytes32[] memory proof
    ) external;
    function finder() external view returns (address);
    function getCurrentTime() external view returns (uint256);
    function haircutReserves(address l1Token, int256 haircutAmount) external;
    function identifier() external view returns (bytes32);
    function liquidityUtilizationCurrent(address l1Token) external returns (uint256);
    function liquidityUtilizationPostRelay(address l1Token, uint256 relayedAmount) external returns (uint256);
    function liveness() external view returns (uint32);
    function loadEthForL2Calls() external payable;
    function lpFeeRatePerSecond() external view returns (uint256);
    function lpTokenFactory() external view returns (address);
    function multicall(bytes[] memory data) external payable returns (bytes[] memory results);
    function owner() external view returns (address);
    function paused() external view returns (bool);
    function poolRebalanceRoute(uint256 destinationChainId, address l1Token)
        external
        view
        returns (address destinationToken);
    function pooledTokens(address)
        external
        view
        returns (
            address lpToken,
            bool isEnabled,
            uint32 lastLpFeeUpdate,
            int256 utilizedReserves,
            uint256 liquidReserves,
            uint256 undistributedLpFees
        );
    function proposeRootBundle(
        uint256[] memory bundleEvaluationBlockNumbers,
        uint8 poolRebalanceLeafCount,
        bytes32 poolRebalanceRoot,
        bytes32 relayerRefundRoot,
        bytes32 slowRelayRoot
    ) external;
    function protocolFeeCaptureAddress() external view returns (address);
    function protocolFeeCapturePct() external view returns (uint256);
    function relaySpokePoolAdminFunction(uint256 chainId, bytes memory functionData) external;
    function removeLiquidity(address l1Token, uint256 lpTokenAmount, bool sendEth) external;
    function renounceOwnership() external;
    function rootBundleProposal()
        external
        view
        returns (
            bytes32 poolRebalanceRoot,
            bytes32 relayerRefundRoot,
            bytes32 slowRelayRoot,
            uint256 claimedBitMap,
            address proposer,
            uint8 unclaimedPoolRebalanceLeafCount,
            uint32 challengePeriodEndTimestamp
        );
    function setBond(address newBondToken, uint256 newBondAmount) external;
    function setCrossChainContracts(uint256 l2ChainId, address adapter, address spokePool) external;
    function setCurrentTime(uint256 time) external;
    function setDepositRoute(
        uint256 originChainId,
        uint256 destinationChainId,
        address originToken,
        bool depositsEnabled
    ) external;
    function setIdentifier(bytes32 newIdentifier) external;
    function setLiveness(uint32 newLiveness) external;
    function setPaused(bool pause) external;
    function setPoolRebalanceRoute(uint256 destinationChainId, address l1Token, address destinationToken) external;
    function setProtocolFeeCapture(address newProtocolFeeCaptureAddress, uint256 newProtocolFeeCapturePct) external;
    function sync(address l1Token) external;
    function timerAddress() external view returns (address);
    function transferOwnership(address newOwner) external;
    function unclaimedAccumulatedProtocolFees(address) external view returns (uint256);
    function weth() external view returns (address);
}
