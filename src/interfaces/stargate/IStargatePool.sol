// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

library StargateBase {
    struct AddressConfig {
        address feeLib;
        address planner;
        address treasurer;
        address tokenMessaging;
        address creditMessaging;
        address lzToken;
    }
}

interface IStargatePool {
    type StargateType is uint8;

    struct Credit {
        uint32 srcEid;
        uint64 amount;
    }

    struct MessagingFee {
        uint256 nativeFee;
        uint256 lzTokenFee;
    }

    struct MessagingReceipt {
        bytes32 guid;
        uint64 nonce;
        MessagingFee fee;
    }

    struct OFTFeeDetail {
        int256 feeAmountLD;
        string description;
    }

    struct OFTLimit {
        uint256 minAmountLD;
        uint256 maxAmountLD;
    }

    struct OFTReceipt {
        uint256 amountSentLD;
        uint256 amountReceivedLD;
    }

    struct Origin {
        uint32 srcEid;
        bytes32 sender;
        uint64 nonce;
    }

    struct SendParam {
        uint32 dstEid;
        bytes32 to;
        uint256 amountLD;
        uint256 minAmountLD;
        bytes extraOptions;
        bytes composeMsg;
        bytes oftCmd;
    }

    struct TargetCredit {
        uint32 srcEid;
        uint64 amount;
        uint64 minAmount;
    }

    struct Ticket {
        uint72 ticketId;
        bytes passengerBytes;
    }

    error InvalidLocalDecimals();
    error Path_AlreadyHasCredit();
    error Path_InsufficientCredit();
    error Path_UnlimitedCredit();
    error SlippageExceeded(uint256 amountLD, uint256 minAmountLD);
    error Stargate_InsufficientFare();
    error Stargate_InvalidAmount();
    error Stargate_InvalidPath();
    error Stargate_InvalidTokenDecimals();
    error Stargate_LzTokenUnavailable();
    error Stargate_OnlyTaxi();
    error Stargate_OutflowFailed();
    error Stargate_Paused();
    error Stargate_RecoverTokenUnsupported();
    error Stargate_ReentrantCall();
    error Stargate_SlippageTooHigh();
    error Stargate_Unauthorized();
    error Stargate_UnreceivedTokenNotFound();
    error Transfer_ApproveFailed();
    error Transfer_TransferFailed();

    event AddressConfigSet(StargateBase.AddressConfig config);
    event CreditsReceived(uint32 srcEid, Credit[] credits);
    event CreditsSent(uint32 dstEid, Credit[] credits);
    event Deposited(address indexed payer, address indexed receiver, uint256 amountLD);
    event OFTPathSet(uint32 dstEid, bool oft);
    event OFTReceived(bytes32 indexed guid, uint32 srcEid, address indexed toAddress, uint256 amountReceivedLD);
    event OFTSent(
        bytes32 indexed guid, uint32 dstEid, address indexed fromAddress, uint256 amountSentLD, uint256 amountReceivedLD
    );
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PauseSet(bool paused);
    event PlannerFeeWithdrawn(uint256 amount);
    event Redeemed(address indexed payer, address indexed receiver, uint256 amountLD);
    event TreasuryFeeAdded(uint64 amountSD);
    event TreasuryFeeWithdrawn(address to, uint64 amountSD);
    event UnreceivedTokenCached(
        bytes32 guid, uint8 index, uint32 srcEid, address receiver, uint256 amountLD, bytes composeMsg
    );

    fallback() external payable;

    receive() external payable;

    function addTreasuryFee(uint256 _amountLD) external payable;
    function approvalRequired() external pure returns (bool);
    function deficitOffset() external view returns (uint256);
    function deposit(address _receiver, uint256 _amountLD) external payable returns (uint256 amountLD);
    function endpoint() external view returns (address);
    function getAddressConfig() external view returns (StargateBase.AddressConfig memory);
    function getTransferGasLimit() external view returns (uint256);
    function localEid() external view returns (uint32);
    function lpToken() external view returns (address);
    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version);
    function owner() external view returns (address);
    function paths(uint32 eid) external view returns (uint64 credit);
    function plannerFee() external view returns (uint256 available);
    function poolBalance() external view returns (uint256);
    function quoteOFT(SendParam memory _sendParam)
        external
        view
        returns (OFTLimit memory limit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory receipt);
    function quoteRedeemSend(SendParam memory _sendParam, bool _payInLzToken)
        external
        view
        returns (MessagingFee memory fee);
    function quoteSend(SendParam memory _sendParam, bool _payInLzToken)
        external
        view
        returns (MessagingFee memory fee);
    function receiveCredits(uint32 _srcEid, Credit[] memory _credits) external;
    function receiveTokenBus(
        Origin memory _origin,
        bytes32 _guid,
        uint8 _seatNumber,
        address _receiver,
        uint64 _amountSD
    ) external;
    function receiveTokenTaxi(
        Origin memory _origin,
        bytes32 _guid,
        address _receiver,
        uint64 _amountSD,
        bytes memory _composeMsg
    ) external;
    function recoverToken(address _token, address _to, uint256 _amount) external returns (uint256);
    function redeem(uint256 _amountLD, address _receiver) external returns (uint256 amountLD);
    function redeemSend(SendParam memory _sendParam, MessagingFee memory _fee, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt);
    function redeemable(address _owner) external view returns (uint256 amountLD);
    function renounceOwnership() external;
    function retryReceiveToken(
        bytes32 _guid,
        uint8 _index,
        uint32 _srcEid,
        address _receiver,
        uint256 _amountLD,
        bytes memory _composeMsg
    ) external;
    function send(SendParam memory _sendParam, MessagingFee memory _fee, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt);
    function sendCredits(uint32 _dstEid, TargetCredit[] memory _credits) external returns (Credit[] memory);
    function sendToken(SendParam memory _sendParam, MessagingFee memory _fee, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt, Ticket memory ticket);
    function setAddressConfig(StargateBase.AddressConfig memory _config) external;
    function setDeficitOffset(uint256 _deficitOffsetLD) external;
    function setOFTPath(uint32 _dstEid, bool _oft) external;
    function setPause(bool _paused) external;
    function setTransferGasLimit(uint256 _gasLimit) external;
    function sharedDecimals() external view returns (uint8);
    function stargateType() external pure returns (StargateType);
    function status() external view returns (uint8);
    function token() external view returns (address);
    function transferOwnership(address newOwner) external;
    function treasuryFee() external view returns (uint64);
    function tvl() external view returns (uint256);
    function unreceivedTokens(bytes32 guid, uint8 index) external view returns (bytes32 hash);
    function withdrawPlannerFee() external;
    function withdrawTreasuryFee(address _to, uint64 _amountSD) external;
}
