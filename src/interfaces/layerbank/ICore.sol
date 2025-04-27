// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library Constant {
    struct MarketInfo {
        bool isListed;
        uint256 supplyCap;
        uint256 borrowCap;
        uint256 collateralFactor;
    }
}

interface ICore {
    event BorrowCapUpdated(address indexed lToken, uint256 newBorrowCap);
    event CloseFactorUpdated(uint256 newCloseFactor);
    event CollateralFactorUpdated(address lToken, uint256 newCollateralFactor);
    event FlashLoan(
        address indexed target, address indexed initiator, address indexed asset, uint256 amount, uint256 premium
    );
    event KeeperUpdated(address newKeeper);
    event LABDistributorUpdated(address newLABDistributor);
    event LeveragerUpdated(address newLeverager);
    event LiquidationIncentiveUpdated(uint256 newLiquidationIncentive);
    event MarketEntered(address lToken, address account);
    event MarketExited(address lToken, address account);
    event MarketListed(address lToken);
    event MarketRedeem(address user, address lToken, uint256 uAmount);
    event MarketSupply(address user, address lToken, uint256 uAmount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event RebateDistributorUpdated(address newRebateDistributor);
    event SupplyCapUpdated(address indexed lToken, uint256 newSupplyCap);
    event Unpaused(address account);
    event ValidatorUpdated(address newValidator);

    function accountLiquidityOf(address account)
        external
        view
        returns (uint256 collateralInUSD, uint256 supplyInUSD, uint256 borrowInUSD);
    function allMarkets() external view returns (address[] memory);
    function borrow(address lToken, uint256 amount) external;
    function borrowBehalf(address borrower, address lToken, uint256 amount) external;
    function checkMembership(address account, address lToken) external view returns (bool);
    function claimLab() external;
    function claimLab(address market) external;
    function claimLabBehalf(address[] memory accounts) external;
    function closeFactor() external view returns (uint256);
    function compoundLab(uint256 lockDuration) external;
    function enterMarkets(address[] memory lTokens) external;
    function exitMarket(address lToken) external;
    function initialize(address _priceCalculator) external;
    function initialized() external view returns (bool);
    function keeper() external view returns (address);
    function labDistributor() external view returns (address);
    function leverager() external view returns (address);
    function liquidateBorrow(address lTokenBorrowed, address lTokenCollateral, address borrower, uint256 amount)
        external
        payable;
    function liquidationIncentive() external view returns (uint256);
    function listMarket(address payable lToken, uint256 supplyCap, uint256 borrowCap, uint256 collateralFactor)
        external;
    function marketInfoOf(address lToken) external view returns (Constant.MarketInfo memory);
    function marketInfos(address)
        external
        view
        returns (bool isListed, uint256 supplyCap, uint256 borrowCap, uint256 collateralFactor);
    function marketListOf(address account) external view returns (address[] memory);
    function marketListOfUsers(address, uint256) external view returns (address);
    function markets(uint256) external view returns (address);
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function priceCalculator() external view returns (address);
    function rebateDistributor() external view returns (address);
    function redeemToken(address lToken, uint256 lAmount) external returns (uint256);
    function redeemUnderlying(address lToken, uint256 uAmount) external returns (uint256);
    function removeMarket(address payable lToken) external;
    function renounceOwnership() external;
    function repayBorrow(address lToken, uint256 amount) external payable;
    function setCloseFactor(uint256 newCloseFactor) external;
    function setCollateralFactor(address lToken, uint256 newCollateralFactor) external;
    function setKeeper(address _keeper) external;
    function setLABDistributor(address _labDistributor) external;
    function setLeverager(address _leverager) external;
    function setLiquidationIncentive(uint256 newLiquidationIncentive) external;
    function setMarketBorrowCaps(address[] memory lTokens, uint256[] memory newBorrowCaps) external;
    function setMarketSupplyCaps(address[] memory lTokens, uint256[] memory newSupplyCaps) external;
    function setPriceCalculator(address _priceCalculator) external;
    function setRebateDistributor(address _rebateDistributor) external;
    function setValidator(address _validator) external;
    function supply(address lToken, uint256 uAmount) external payable returns (uint256);
    function supplyBehalf(address supplier, address lToken, uint256 uAmount) external payable returns (uint256);
    function transferOwnership(address newOwner) external;
    function transferTokens(address spender, address src, address dst, uint256 amount) external;
    function unpause() external;
    function usersOfMarket(address, address) external view returns (bool);
    function validator() external view returns (address);
}
