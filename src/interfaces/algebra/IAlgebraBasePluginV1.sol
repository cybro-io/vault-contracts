// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IAlgebraBasePluginV1 {
    struct AlgebraFeeConfiguration {
        uint16 alpha1;
        uint16 alpha2;
        uint32 beta1;
        uint32 beta2;
        uint16 gamma1;
        uint16 gamma2;
        uint16 baseFee;
    }

    error AddressZero();
    error targetIsTooOld();
    error volatilityOracleAlreadyInitialized();

    event FeeConfiguration(AlgebraFeeConfiguration feeConfig);
    event Incentive(address newIncentive);
    event Initialized(uint8 version);

    function ALGEBRA_BASE_PLUGIN_MANAGER() external view returns (bytes32);
    function afterFlash(address, address, uint256, uint256, uint256, uint256, bytes memory) external returns (bytes4);
    function afterInitialize(address, uint160, int24 tick) external returns (bytes4);
    function afterModifyPosition(address, address, int24, int24, int128, uint256, uint256, bytes memory)
        external
        returns (bytes4);
    function afterSwap(address, address, bool zeroToOne, int256, uint160, int256, int256, bytes memory)
        external
        returns (bytes4);
    function beforeFlash(address, address, uint256, uint256, bytes memory) external returns (bytes4);
    function beforeInitialize(address, uint160) external returns (bytes4);
    function beforeModifyPosition(address, address, int24, int24, int128, bytes memory) external returns (bytes4);
    function beforeSwap(address, address, bool, int256, uint160, bool, bytes memory) external returns (bytes4);
    function changeFeeConfiguration(AlgebraFeeConfiguration memory _config) external;
    function defaultPluginConfig() external view returns (uint8);
    function feeConfig()
        external
        view
        returns (uint16 alpha1, uint16 alpha2, uint32 beta1, uint32 beta2, uint16 gamma1, uint16 gamma2, uint16 baseFee);
    function getCurrentFee() external view returns (uint16 fee);
    function getSingleTimepoint(uint32 secondsAgo)
        external
        view
        returns (int56 tickCumulative, uint88 volatilityCumulative);
    function getTimepoints(uint32[] memory secondsAgos)
        external
        view
        returns (int56[] memory tickCumulatives, uint88[] memory volatilityCumulatives);
    function incentive() external view returns (address);
    function initialize() external;
    function initialize(address _blastGovernor, address _pool, address _factory, address _pluginFactory) external;
    function isIncentiveConnected(address targetIncentive) external view returns (bool);
    function isInitialized() external view returns (bool);
    function lastTimepointTimestamp() external view returns (uint32);
    function pool() external view returns (address);
    function prepayTimepointsStorageSlots(uint16 startIndex, uint16 amount) external;
    function setIncentive(address newIncentive) external;
    function timepointIndex() external view returns (uint16);
    function timepoints(uint256)
        external
        view
        returns (
            bool initialized,
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint88 volatilityCumulative,
            int24 tick,
            int24 averageTick,
            uint16 windowStartIndex
        );
}
