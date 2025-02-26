// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IFeeProvider} from "./interfaces/IFeeProvider.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title FeeProvider
 * @notice A contract for managing fees for users
 */
contract FeeProvider is IFeeProvider, OwnableUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    struct UserFees {
        bool initialized;
        uint32 depositFee;
        uint32 withdrawalFee;
        uint32 performanceFee;
    }

    struct StakedAmount {
        uint256 stakedAmount;
        uint256 deadline;
    }

    struct TierData {
        uint32 discount;
        uint256 minAmount;
    }

    /* ========== EVENTS ========== */

    event GlobalDepositFeeUpdated(uint32 newDepositFee);
    event GlobalWithdrawalFeeUpdated(uint32 newWithdrawalFee);
    event GlobalPerformanceFeeUpdated(uint32 newPerformanceFee);
    event ManagementFeeUpdated(uint32 newManagementFee);

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

    uint32 private _managementFee;

    mapping(address user => StakedAmount stakedAmount) private _stakedAmounts;
    mapping(address signer => bool isSigner) public signers;
    uint8[] public discountTiers;
    mapping(uint8 tier => TierData tierData) public tiersData;

    /* ========== CONSTRUCTOR ========== */

    constructor(uint32 feePrecision) {
        _feePrecision = feePrecision;
        _disableInitializers();
    }

    /* ========== INITIALIZER ========== */

    function initialize(
        address admin,
        uint32 depositFee,
        uint32 withdrawalFee,
        uint32 performanceFee,
        uint32 managementFee
    ) public initializer {
        __Ownable_init(admin);
        _depositFee = depositFee;
        _withdrawalFee = withdrawalFee;
        _performanceFee = performanceFee;
        _managementFee = managementFee;
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
     * @notice Sets the management fee
     * @param managementFee The management fee
     */
    function setmanagementFee(uint32 managementFee) external onlyOwner {
        _managementFee = managementFee;
        emit ManagementFeeUpdated(managementFee);
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

        depositFee = _applyDiscount(depositFee, user);
        withdrawalFee = _applyDiscount(withdrawalFee, user);
        performanceFee = _applyDiscount(performanceFee, user);
    }

    function setTiers(uint8[] memory discountTiers_, uint32[] memory discounts_, uint256[] memory minAmounts_)
        external
        onlyOwner
    {
        require(discountTiers_.length == discounts_.length && discounts_.length == minAmounts_.length);
        discountTiers = discountTiers_;
        for (uint8 i = 0; i < discountTiers_.length; i++) {
            tiersData[discountTiers_[i]] = TierData({discount: discounts_[i], minAmount: minAmounts_[i]});
        }
    }

    function setStakedAmount(address user, uint256 stakedAmount, uint256 deadline, bytes memory signature) external {
        require(stakedAmount > 0, "FeeProvider: stakedAmount must be greater than 0");
        require(block.timestamp <= deadline, "FeeProvider: expired signature");
        address signer_ =
            keccak256(abi.encodePacked(user, stakedAmount, deadline)).toEthSignedMessageHash().recover(signature);
        require(signers[signer_]);
        _stakedAmounts[user] = StakedAmount({stakedAmount: stakedAmount, deadline: deadline});
    }

    function setStakedAmounts(address[] memory users_, uint256[] memory stakedAmounts_, uint256[] memory deadlines_)
        external
        onlyOwner
    {
        require(users_.length == stakedAmounts_.length);
        for (uint256 i = 0; i < users_.length; i++) {
            _stakedAmounts[users_[i]] = StakedAmount({stakedAmount: stakedAmounts_[i], deadline: deadlines_[i]});
        }
    }

    function setSigners(address[] memory signers_, bool[] memory isSigner_) external onlyOwner {
        require(signers_.length == isSigner_.length);
        for (uint256 i = 0; i < signers_.length; i++) {
            signers[signers_[i]] = isSigner_[i];
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
        return _applyDiscount(
            _users[user].initialized ? uint32(Math.min(_depositFee, _users[user].depositFee)) : _depositFee, user
        );
    }

    /**
     * @notice Returns the withdrawal fee for an account
     * @param user The address of the user
     * @return The withdrawal fee
     */
    function getWithdrawalFee(address user) external view returns (uint32) {
        return _applyDiscount(
            _users[user].initialized ? uint32(Math.min(_withdrawalFee, _users[user].withdrawalFee)) : _withdrawalFee,
            user
        );
    }

    /**
     * @notice Returns the performance fee for an account
     * @param user The address of the user
     * @return The performance fee
     */
    function getPerformanceFee(address user) external view returns (uint32) {
        return _applyDiscount(
            _users[user].initialized ? uint32(Math.min(_performanceFee, _users[user].performanceFee)) : _performanceFee,
            user
        );
    }

    /**
     * @notice Returns the management fee.
     * @return The management fee.
     */
    function getManagementFee() external view returns (uint32) {
        return _managementFee;
    }

    function getDiscount(address user) public view returns (uint32) {
        if (_stakedAmounts[user].deadline < block.timestamp) return 0;
        uint256 amount = _stakedAmounts[user].stakedAmount;
        for (uint8 i = uint8(discountTiers.length); i > 0; i--) {
            TierData memory tierData = tiersData[discountTiers[i - 1]];
            if (amount >= tierData.minAmount) return tierData.discount;
        }
        return 0;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _applyDiscount(uint32 fee, address user) internal view returns (uint32) {
        return fee * (_feePrecision - getDiscount(user)) / _feePrecision;
    }
}
