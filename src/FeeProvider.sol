// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";

contract FeeProvider is IFeeProvider, OwnableUpgradeable {
    uint32 private immutable _feePrecision;

    uint32 private _depositFee;
    uint32 private _withdrawalFee;
    uint32 private _performanceFee;

    constructor(uint32 feePrecision) {
        _feePrecision = feePrecision;
        _disableInitializers();
    }

    function initialize(address admin, uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee)
        public
        initializer
    {
        __Ownable_init(admin);
        _depositFee = depositFee;
        _withdrawalFee = withdrawalFee;
        _performanceFee = performanceFee;
    }

    function setFees(uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee) external onlyOwner {
        _depositFee = depositFee;
        _withdrawalFee = withdrawalFee;
        _performanceFee = performanceFee;
    }

    function getFeePrecision() external view returns (uint32) {
        return _feePrecision;
    }

    function getDepositFee(address) external view returns (uint32) {
        return _depositFee;
    }

    function getWithdrawalFee(address) external view returns (uint32) {
        return _withdrawalFee;
    }

    function getPerformanceFee(address) external view returns (uint32) {
        return _performanceFee;
    }
}
