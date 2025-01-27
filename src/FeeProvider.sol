// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title FeeProvider
 * @notice A contract for managing fees for users
 */
contract FeeProvider is IFeeProvider, OwnableUpgradeable {
    struct UserFees {
        bool initialized;
        uint32 depositFee;
        uint32 withdrawalFee;
        uint32 performanceFee;
    }

    /* ========== EVENTS ========== */

    event GlobalDepositFeeUpdated(uint32 newDepositFee);
    event GlobalWithdrawalFeeUpdated(uint32 newWithdrawalFee);
    event GlobalPerformanceFeeUpdated(uint32 newPerformanceFee);

    /* ========== IMMUTABLE VARIABLES ========== */

    uint32 private immutable _feePrecision;

    /* ========== STATE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    uint32 private _depositFee;
    uint32 private _withdrawalFee;
    uint32 private _performanceFee;

    /// @notice The mapping of users and their fees
    mapping(address user => UserFees fees) private _users;

    /// @notice Mapping of contracts that are allowed to update user fees
    mapping(address contractAddress => bool isWhitelisted) public whitelistedContracts;

    /* ========== CONSTRUCTOR ========== */

    constructor(uint32 feePrecision) {
        _feePrecision = feePrecision;
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

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

    /**
     * @notice Sets the whitelisted contracts
     * @param contracts The addresses of the contracts
     * @param isWhitelisted Whether the contracts are whitelisted with the FeeProvider
     */
    function setWhitelistedContracts(address[] memory contracts, bool[] memory isWhitelisted) external onlyOwner {
        for (uint256 i = 0; i < contracts.length; i++) {
            whitelistedContracts[contracts[i]] = isWhitelisted[i];
        }
    }

    /**
     * @notice Sets the global fees
     * @param depositFee The deposit fee
     * @param withdrawalFee The withdrawal fee
     * @param performanceFee The performance fee
     */
    function setFees(uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee) external onlyOwner {
        if (_depositFee != depositFee) emit GlobalDepositFeeUpdated(depositFee);
        if (_withdrawalFee != withdrawalFee) emit GlobalWithdrawalFeeUpdated(withdrawalFee);
        if (_performanceFee != performanceFee) emit GlobalPerformanceFeeUpdated(performanceFee);
        _depositFee = depositFee;
        _withdrawalFee = withdrawalFee;
        _performanceFee = performanceFee;
    }

    /**
     * @notice Sets the fees for multiple users
     * @param users The addresses of the users
     * @param depositFees The deposit fees for the users
     * @param withdrawalFees The withdrawal fees for the users
     * @param performanceFees The performance fees for the users
     */
    function setFeesForUsers(
        address[] memory users,
        uint32[] memory depositFees,
        uint32[] memory withdrawalFees,
        uint32[] memory performanceFees
    ) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            UserFees storage userFees = _users[users[i]];
            userFees.initialized = true;
            // we don't need to verify that global fees are lower than user fees
            // because it will be automatically checked in getUpdateUserFees
            userFees.depositFee = uint32(Math.min(depositFees[i], userFees.depositFee));
            userFees.withdrawalFee = uint32(Math.min(withdrawalFees[i], userFees.withdrawalFee));
            userFees.performanceFee = uint32(Math.min(performanceFees[i], userFees.performanceFee));
        }
    }

    /**
     * @notice Returns and updates the fees for a user
     * @param user The address of the user
     * @return depositFee The deposit fee of the user
     * @return withdrawalFee The withdrawal fee of the user
     * @return performanceFee The performance fee of the user
     */
    function getUpdateUserFees(address user)
        external
        returns (uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee)
    {
        UserFees storage userFees = _users[user];
        bool isWhitelistedContract = whitelistedContracts[msg.sender];
        if (!userFees.initialized) {
            depositFee = _depositFee;
            withdrawalFee = _withdrawalFee;
            performanceFee = _performanceFee;
        } else {
            depositFee = uint32(Math.min(_depositFee, userFees.depositFee));
            withdrawalFee = uint32(Math.min(_withdrawalFee, userFees.withdrawalFee));
            performanceFee = uint32(Math.min(_performanceFee, userFees.performanceFee));
        }

        if (isWhitelistedContract) {
            userFees.initialized = true;
            userFees.depositFee = depositFee;
            userFees.withdrawalFee = withdrawalFee;
            userFees.performanceFee = performanceFee;
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Returns the fee precision
     * @return The fee precision
     */
    function getFeePrecision() external view returns (uint32) {
        return _feePrecision;
    }

    /**
     * @notice Returns the deposit fee for an account
     * @param user The address of the user
     * @return The deposit fee
     */
    function getDepositFee(address user) external view returns (uint32) {
        return _users[user].initialized ? uint32(Math.min(_depositFee, _users[user].depositFee)) : _depositFee;
    }

    /**
     * @notice Returns the withdrawal fee for an account
     * @param user The address of the user
     * @return The withdrawal fee
     */
    function getWithdrawalFee(address user) external view returns (uint32) {
        return _users[user].initialized ? uint32(Math.min(_withdrawalFee, _users[user].withdrawalFee)) : _withdrawalFee;
    }

    /**
     * @notice Returns the performance fee for an account
     * @param user The address of the user
     * @return The performance fee
     */
    function getPerformanceFee(address user) external view returns (uint32) {
        return
            _users[user].initialized ? uint32(Math.min(_performanceFee, _users[user].performanceFee)) : _performanceFee;
    }
}
