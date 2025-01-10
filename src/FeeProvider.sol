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
    /**
     * @custom:storage-location erc7201:cybro.storage.FeeProvider
     * @param depositFee The global deposit fee
     * @param withdrawalFee The global withdrawal fee
     * @param performanceFee The global performance fee
     * @param users The mapping of users and their fees
     * @param whitelistedContracts The mapping of contracts that are allowed to update user fees
     */
    struct FeeProviderStorage {
        uint32 depositFee;
        uint32 withdrawalFee;
        uint32 performanceFee;
        uint32 administrationFee;
        mapping(address user => UserFees fees) users;
        mapping(address contractAddress => bool isWhitelisted) whitelistedContracts;
    }

    function _getFeeProviderStorage() private pure returns (FeeProviderStorage storage $) {
        assembly {
            $.slot := FEE_PROVIDER_STORAGE_LOCATION
        }
    }

    struct UserFees {
        bool initialized;
        uint32 depositFee;
        uint32 withdrawalFee;
        uint32 performanceFee;
    }

    /* ========== EVENTS ========== */

    event GlobbalDepositFeeUpdated(uint32 newDepositFee);
    event GlobbalWithdrawalFeeUpdated(uint32 newWithdrawalFee);
    event GlobbalPerformanceFeeUpdated(uint32 newPerformanceFee);
    event AdministrationFeeUpdated(uint32 newAdministrationFee);

    /* ========== CONSTANTS ========== */

    // keccak256(abi.encode(uint256(keccak256("cybro.storage.FeeProvider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FEE_PROVIDER_STORAGE_LOCATION =
        0x5a3f433112e5f6f2d07abf89dabbd357876e4b5e6bbd594e3e68f92dd92e7a00;

    /* ========== IMMUTABLE VARIABLES ========== */

    uint32 private immutable _feePrecision;
    uint32 private immutable _maxAdministrationFee;

    /* ========== CONSTRUCTOR ========== */

    constructor(uint32 feePrecision, uint32 maxAdministrationFee) {
        _feePrecision = feePrecision;
        _maxAdministrationFee = maxAdministrationFee;
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    function initialize(
        address admin,
        uint32 depositFee,
        uint32 withdrawalFee,
        uint32 performanceFee,
        uint32 administrationFee
    ) public initializer {
        __Ownable_init(admin);
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        $.depositFee = depositFee;
        $.withdrawalFee = withdrawalFee;
        $.performanceFee = performanceFee;
        $.administrationFee = administrationFee < _maxAdministrationFee ? administrationFee : _maxAdministrationFee;
    }

    /* ========== EXTERNAL FUNCTIONS ========== */

    /**
     * @notice Sets the whitelisted contracts
     * @param contracts The addresses of the contracts
     * @param isWhitelisted Whether the contracts are whitelisted with the FeeProvider
     */
    function setWhitelistedContracts(address[] memory contracts, bool[] memory isWhitelisted) external onlyOwner {
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        for (uint256 i = 0; i < contracts.length; i++) {
            $.whitelistedContracts[contracts[i]] = isWhitelisted[i];
        }
    }

    /**
     * @notice Sets the administration fee
     * @param administrationFee The administration fee
     */
    function setAdministrationFee(uint32 administrationFee) external onlyOwner {
        require(administrationFee <= _maxAdministrationFee, "FeeProvider: invalid administration fee");
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        $.administrationFee = administrationFee;
        emit AdministrationFeeUpdated(administrationFee);
    }

    /**
     * @notice Sets the global fees
     * @param depositFee The deposit fee
     * @param withdrawalFee The withdrawal fee
     * @param performanceFee The performance fee
     */
    function setFees(uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee) external onlyOwner {
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        if ($.depositFee != depositFee) emit GlobbalDepositFeeUpdated(depositFee);
        if ($.withdrawalFee != withdrawalFee) emit GlobbalWithdrawalFeeUpdated(withdrawalFee);
        if ($.performanceFee != performanceFee) emit GlobbalPerformanceFeeUpdated(performanceFee);
        $.depositFee = depositFee;
        $.withdrawalFee = withdrawalFee;
        $.performanceFee = performanceFee;
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
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        for (uint256 i = 0; i < users.length; i++) {
            UserFees storage userFees = $.users[users[i]];
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
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        UserFees storage userFees = $.users[user];
        bool isWhitelistedContract = $.whitelistedContracts[msg.sender];
        if (!userFees.initialized) {
            depositFee = $.depositFee;
            withdrawalFee = $.withdrawalFee;
            performanceFee = $.performanceFee;
        } else {
            depositFee = uint32(Math.min($.depositFee, userFees.depositFee));
            withdrawalFee = uint32(Math.min($.withdrawalFee, userFees.withdrawalFee));
            performanceFee = uint32(Math.min($.performanceFee, userFees.performanceFee));
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
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        return $.users[user].initialized ? uint32(Math.min($.depositFee, $.users[user].depositFee)) : $.depositFee;
    }

    /**
     * @notice Returns the withdrawal fee for an account
     * @param user The address of the user
     * @return The withdrawal fee
     */
    function getWithdrawalFee(address user) external view returns (uint32) {
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        return
            $.users[user].initialized ? uint32(Math.min($.withdrawalFee, $.users[user].withdrawalFee)) : $.withdrawalFee;
    }

    /**
     * @notice Returns the performance fee for an account
     * @param user The address of the user
     * @return The performance fee
     */
    function getPerformanceFee(address user) external view returns (uint32) {
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        return $.users[user].initialized
            ? uint32(Math.min($.performanceFee, $.users[user].performanceFee))
            : $.performanceFee;
    }

    /**
     * @notice Returns the administration fee
     * @return The administration fee
     */
    function getAdministrationFee() external view returns (uint32) {
        FeeProviderStorage storage $ = _getFeeProviderStorage();
        return $.administrationFee;
    }

    function getMaxAdministrationFee() external view returns (uint32) {
        return _maxAdministrationFee;
    }
}
