// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FeeProvider is IFeeProvider, OwnableUpgradeable {
    struct UserFees {
        bool initialized;
        uint32 depositFee;
        uint32 withdrawalFee;
        uint32 performanceFee;
    }

    uint32 private immutable _feePrecision;

    uint32 private _depositFee;
    uint32 private _withdrawalFee;
    uint32 private _performanceFee;

    mapping(address user => UserFees fees) private _users;
    mapping(address contractAddress => bool isAssociated) public associatedContracts;

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

    /* ========== EXTERNAL FUNCTIONS ========== */

    function setAssociatedContracts(address[] memory contracts, bool[] memory isAssociated) external onlyOwner {
        for (uint256 i = 0; i < contracts.length; i++) {
            associatedContracts[contracts[i]] = isAssociated[i];
        }
    }

    function setFees(uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee) external onlyOwner {
        _depositFee = depositFee;
        _withdrawalFee = withdrawalFee;
        _performanceFee = performanceFee;
    }

    function setFeesForUsers(
        address[] memory users,
        uint32[] memory depositFees,
        uint32[] memory withdrawalFees,
        uint32[] memory performanceFees
    ) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            UserFees storage userFees = _users[users[i]];
            if (userFees.initialized) {
                require(depositFees[i] <= userFees.depositFee, "FeeProvider: invalid deposit fee");
                require(withdrawalFees[i] <= userFees.withdrawalFee, "FeeProvider: invalid withdrawal fee");
                require(performanceFees[i] <= userFees.performanceFee, "FeeProvider: invalid performance fee");
            } else {
                userFees.initialized = true;
            }
            // we don't need to verify that global fees are lower than user fees
            // because it will be automatically checked in updateUserFees modifier
            userFees.depositFee = depositFees[i];
            userFees.withdrawalFee = withdrawalFees[i];
            userFees.performanceFee = performanceFees[i];
        }
    }

    function getUpdateUserFees(address user)
        external
        returns (uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee)
    {
        bool isAssociatedContract = associatedContracts[msg.sender];
        UserFees storage userFees = _users[user];
        if (!userFees.initialized) {
            depositFee = _depositFee;
            withdrawalFee = _withdrawalFee;
            performanceFee = _performanceFee;
        } else {
            depositFee = _min(_depositFee, userFees.depositFee);
            withdrawalFee = _min(_withdrawalFee, userFees.withdrawalFee);
            performanceFee = _min(_performanceFee, userFees.performanceFee);
        }

        if (isAssociatedContract) {
            userFees.initialized = true;
            userFees.depositFee = depositFee;
            userFees.withdrawalFee = withdrawalFee;
            userFees.performanceFee = performanceFee;
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Returns the fee precision
    /// @return The fee precision
    function getFeePrecision() external view returns (uint32) {
        return _feePrecision;
    }

    /// @notice Returns the deposit fee for an account
    /// @param user The address of the user
    /// @return The deposit fee
    function getDepositFee(address user) external view returns (uint32) {
        return _users[user].initialized ? _min(_depositFee, _users[user].depositFee) : _depositFee;
    }

    /// @notice Returns the withdrawal fee for an account
    /// @param user The address of the user
    /// @return The withdrawal fee
    function getWithdrawalFee(address user) external view returns (uint32) {
        return _users[user].initialized ? _min(_withdrawalFee, _users[user].withdrawalFee) : _withdrawalFee;
    }

    /// @notice Returns the performance fee for an account
    /// @param user The address of the user
    /// @return The performance fee
    function getPerformanceFee(address user) external view returns (uint32) {
        return _users[user].initialized ? _min(_performanceFee, _users[user].performanceFee) : _performanceFee;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _min(uint32 a, uint32 b) internal pure returns (uint32) {
        return a < b ? a : b;
    }
}
