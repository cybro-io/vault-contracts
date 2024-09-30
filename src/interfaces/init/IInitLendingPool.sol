// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IInitLendingPool {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Initialized(uint8 version);
    event SetIrm(address _irm);
    event SetReserveFactor_e18(uint256 _reserveFactor_e18);
    event SetTreasury(address _treasury);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function ACM() external view returns (address);
    function accrueInterest() external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function borrow(address _receiver, uint256 _amt) external returns (uint256 shares);
    function burn(address _receiver) external returns (uint256 amt);
    function cash() external view returns (uint256);
    function core() external view returns (address);
    function debtAmtToShareCurrent(uint256 _amt) external returns (uint256 shares);
    function debtAmtToShareStored(uint256 _amt) external view returns (uint256 shares);
    function debtShareToAmtCurrent(uint256 _shares) external returns (uint256 amt);
    function debtShareToAmtStored(uint256 _shares) external view returns (uint256 amt);
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function getBorrowRate_e18() external view returns (uint256 borrowRate_e18);
    function getSupplyRate_e18() external view returns (uint256 supplyRate_e18);
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function initialize(
        address _underlyingToken,
        string memory _name,
        string memory _symbol,
        address _irm,
        uint256 _reserveFactor_e18,
        address _treasury
    ) external;
    function irm() external view returns (address);
    function lastAccruedTime() external view returns (uint256);
    function mint(address _receiver) external returns (uint256 shares);
    function name() external view returns (string memory);
    function repay(uint256 _shares) external returns (uint256 amt);
    function reserveFactor_e18() external view returns (uint256);
    function setIrm(address _irm) external;
    function setReserveFactor_e18(uint256 _reserveFactor_e18) external;
    function setTreasury(address _treasury) external;
    function symbol() external view returns (string memory);
    function toAmt(uint256 _shares) external view returns (uint256 amt);
    function toAmtCurrent(uint256 _shares) external returns (uint256 amt);
    function toShares(uint256 _amt) external view returns (uint256 shares);
    function toSharesCurrent(uint256 _amt) external returns (uint256 shares);
    function totalAssets() external view returns (uint256);
    function totalDebt() external view returns (uint256);
    function totalDebtShares() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function treasury() external view returns (address);
    function underlyingToken() external view returns (address);
}
