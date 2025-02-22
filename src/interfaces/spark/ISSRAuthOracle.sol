// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library ISSROracle {
    struct SUSDSData {
        uint96 ssr;
        uint120 chi;
        uint40 rho;
    }
}

interface ISSRAuthOracle {
    error AccessControlBadConfirmation();
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event SetMaxSSR(uint256 maxSSR);
    event SetSUSDSData(ISSROracle.SUSDSData nextData);

    function DATA_PROVIDER_ROLE() external view returns (bytes32);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function getAPR() external view returns (uint256);
    function getChi() external view returns (uint256);
    function getConversionRate(uint256 timestamp) external view returns (uint256);
    function getConversionRate() external view returns (uint256);
    function getConversionRateBinomialApprox(uint256 timestamp) external view returns (uint256);
    function getConversionRateBinomialApprox() external view returns (uint256);
    function getConversionRateLinearApprox(uint256 timestamp) external view returns (uint256);
    function getConversionRateLinearApprox() external view returns (uint256);
    function getRho() external view returns (uint256);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getSSR() external view returns (uint256);
    function getSUSDSData() external view returns (ISSROracle.SUSDSData memory);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function maxSSR() external view returns (uint256);
    function renounceRole(bytes32 role, address callerConfirmation) external;
    function revokeRole(bytes32 role, address account) external;
    function setMaxSSR(uint256 _maxSSR) external;
    function setSUSDSData(ISSROracle.SUSDSData memory nextData) external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
