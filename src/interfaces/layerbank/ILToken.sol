// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library Constant {
    struct AccountSnapshot {
        uint256 lTokenBalance;
        uint256 borrowBalance;
        uint256 exchangeRate;
    }
}

interface ILToken {
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Borrow(address account, uint256 ammount, uint256 accountBorrow);
    event LiquidateBorrow(
        address liquidator, address borrower, uint256 amount, address lTokenCollateral, uint256 seizeAmount
    );
    event Mint(address minter, uint256 mintAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Redeem(address account, uint256 underlyingAmount, uint256 lTokenAmount);
    event RepayBorrow(address payer, address borrower, uint256 amount, uint256 accountBorrow);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    receive() external payable;

    function _totalBorrow() external view returns (uint256);
    function accInterestIndex() external view returns (uint256);
    function accountSnapshot(address account) external view returns (Constant.AccountSnapshot memory);
    function accruedAccountSnapshot(address account) external returns (Constant.AccountSnapshot memory);
    function accruedBorrowBalanceOf(address account) external returns (uint256);
    function accruedExchangeRate() external returns (uint256);
    function accruedTotalBorrow() external returns (uint256);
    function allowance(address account, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function borrow(address account, uint256 amount) external returns (uint256);
    function borrowBalanceOf(address account) external view returns (uint256);
    function borrowBehalf(address account, address borrower, uint256 amount) external returns (uint256);
    function core() external view returns (address);
    function decimals() external view returns (uint8);
    function exchangeRate() external view returns (uint256);
    function getAccInterestIndex() external view returns (uint256);
    function getCash() external view returns (uint256);
    function getOwner() external view returns (address);
    function getRateModel() external view returns (address);
    function initialize(string memory _name, string memory _symbol, uint8 _decimals) external;
    function initialized() external view returns (bool);
    function lastAccruedTime() external view returns (uint256);
    function liquidateBorrow(address lTokenCollateral, address liquidator, address borrower, uint256 amount)
        external
        payable
        returns (uint256 seizeLAmount, uint256 rebateLAmount, uint256 liquidatorLAmount);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function rateModel() external view returns (address);
    function rebateDistributor() external view returns (address);
    function redeemToken(address redeemer, uint256 lAmount) external returns (uint256);
    function redeemUnderlying(address redeemer, uint256 uAmount) external returns (uint256);
    function renounceOwnership() external;
    function repayBorrow(address account, uint256 amount) external payable returns (uint256);
    function reserveFactor() external view returns (uint256);
    function seize(address liquidator, address borrower, uint256 lAmount) external;
    function setCore(address _core) external;
    function setRateModel(address _rateModel) external;
    function setRebateDistributor(address _rebateDistributor) external;
    function setReserveFactor(uint256 _reserveFactor) external;
    function setUnderlying(address _underlying) external;
    function supply(address account, uint256 uAmount) external payable returns (uint256);
    function supplyBehalf(address account, address supplier, uint256 uAmount) external payable returns (uint256);
    function symbol() external view returns (string memory);
    function totalBorrow() external view returns (uint256);
    function totalReserve() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    function transferOwnership(address newOwner) external;
    function transferTokensInternal(address spender, address src, address dst, uint256 amount) external;
    function underlying() external view returns (address);
    function underlyingBalanceOf(address account) external view returns (uint256);
    function withdrawReserves() external;
}
