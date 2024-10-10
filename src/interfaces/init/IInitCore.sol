// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

/// @dev Obtained via `cast interface 0x815e63d6B5E1b8D74876fC9a2C08b79d4185494b --chain blast`
/// @notice IInitCore

interface IInitCore {
    event Borrow(address indexed pool, uint256 indexed posId, address indexed to, uint256 borrowAmt, uint256 shares);
    event Collateralize(uint256 indexed posId, address indexed pool, uint256 amt);
    event CollateralizeWLp(uint256 indexed posId, address indexed wLp, uint256 indexed tokenId, uint256 amt);
    event CreatePosition(address indexed owner, uint256 indexed posId, uint16 mode, address viewer);
    event Decollateralize(uint256 indexed posId, address indexed pool, address indexed to, uint256 amt);
    event DecollateralizeWLp(
        uint256 indexed posId, address indexed wLp, uint256 indexed tokenId, address to, uint256 amt
    );
    event Initialized(uint8 version);
    event Liquidate(uint256 indexed posId, address indexed liquidator, address poolOut, uint256 shares);
    event LiquidateWLp(uint256 indexed posId, address indexed liquidator, address wLpOut, uint256 tokenId, uint256 amt);
    event Repay(
        address indexed pool, uint256 indexed posId, address indexed repayer, uint256 shares, uint256 amtToRepay
    );
    event SetConfig(address indexed newConfig);
    event SetIncentiveCalculator(address indexed newIncentiveCalculator);
    event SetOracle(address indexed newOracle);
    event SetPositionMode(uint256 indexed posId, uint16 mode);
    event SetRiskManager(address indexed newRiskManager);

    function ACM() external view returns (address);
    function POS_MANAGER() external view returns (address);
    function borrow(address _pool, uint256 _amt, uint256 _posId, address _to) external returns (uint256 shares);
    function burnTo(address _pool, address _to) external returns (uint256 amt);
    function callback(address _to, uint256 _value, bytes memory _data) external payable returns (bytes memory result);
    function collateralize(uint256 _posId, address _pool) external;
    function collateralizeWLp(uint256 _posId, address _wLp, uint256 _tokenId) external;
    function config() external view returns (address);
    function createPos(uint16 _mode, address _viewer) external returns (uint256 posId);
    function decollateralize(uint256 _posId, address _pool, uint256 _shares, address _to) external;
    function decollateralizeWLp(uint256 _posId, address _wLp, uint256 _tokenId, uint256 _amt, address _to) external;
    function flash(address[] memory _pools, uint256[] memory _amts, bytes memory _data) external;
    function getBorrowCreditCurrent_e36(uint256 _posId) external returns (uint256 borrowCredit_e36);
    function getCollateralCreditCurrent_e36(uint256 _posId) external returns (uint256 collCredit_e36);
    function getPosHealthCurrent_e18(uint256 _posId) external returns (uint256 health_e18);
    function getRevertMessage(bytes memory _data) external pure returns (string memory);
    function initialize(address _config, address _oracle, address _liqIncentiveCalculator, address _riskManager)
        external;
    function liqIncentiveCalculator() external view returns (address);
    function liquidate(uint256 _posId, address _poolToRepay, uint256 _repayShares, address _poolOut, uint256 _minShares)
        external
        returns (uint256 shares);
    function liquidateWLp(
        uint256 _posId,
        address _poolToRepay,
        uint256 _repayShares,
        address _wLp,
        uint256 _tokenId,
        uint256 _minlpOut
    ) external returns (uint256 lpAmtOut);
    function mintTo(address _pool, address _to) external returns (uint256 shares);
    function multicall(bytes[] memory data) external payable returns (bytes[] memory results);
    function oracle() external view returns (address);
    function repay(address _pool, uint256 _shares, uint256 _posId) external returns (uint256 amt);
    function riskManager() external view returns (address);
    function setConfig(address _config) external;
    function setLiqIncentiveCalculator(address _liqIncentiveCalculator) external;
    function setOracle(address _oracle) external;
    function setPosMode(uint256 _posId, uint16 _mode) external;
    function setRiskManager(address _riskManager) external;
    function transferToken(address _token, address _to, uint256 _amt) external;
}
