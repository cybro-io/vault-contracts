// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

interface IFeeProvider {
    function getDepositFee(address) external view returns (uint32);
    function getWithdrawalFee(address) external view returns (uint32);
    function getPerformanceFee(address) external view returns (uint32);
    function getFeePrecision() external view returns (uint32);
    function setFees(uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee) external;
}