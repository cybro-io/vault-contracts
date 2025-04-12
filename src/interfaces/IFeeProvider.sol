// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

interface IFeeProvider {
    function getDepositFee(address) external view returns (uint32);
    function getWithdrawalFee(address) external view returns (uint32);
    function getPerformanceFee(address) external view returns (uint32);
    function getManagementFee() external view returns (uint32);
    function getFeePrecision() external view returns (uint32);
    function getDiscount(address user) external view returns (uint32);
    function stakedAmountInfo(address user) external view returns (uint256 stakedAmount, uint256 deadline);
    function setFees(uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee) external;
    function getUpdateUserFees(address user)
        external
        returns (uint32 depositFee, uint32 withdrawalFee, uint32 performanceFee);
    function setWhitelistedContracts(address[] memory contracts, bool[] memory isAssociated) external;
    function setStakedAmount(address user, uint256 stakedAmount, uint256 deadline, bytes memory signature) external;
    function setStakedAmounts(address[] memory users, uint256[] memory stakedAmounts, uint256[] memory deadlines)
        external;
    function setTiers(uint8[] memory discountTiers, uint32[] memory discounts, uint256[] memory minAmounts) external;
    function setSigners(address[] memory signers, bool[] memory isSigner) external;
    function whitelistedContracts(address contractAddress) external view returns (bool isWhitelisted);
    function signers(address signer) external view returns (bool isSigner);
    function tiersData(uint8 tier) external view returns (uint32 discount, uint256 minAmount);
}
