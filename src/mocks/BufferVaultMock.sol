// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.26;

import {BufferVault} from "../BufferVault.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFeeProvider} from "../interfaces/IFeeProvider.sol";

contract BufferVaultMock is BufferVault {
    using SafeERC20 for IERC20Metadata;

    constructor(IERC20Metadata _asset, IFeeProvider _feeProvider, address _feeRecipient)
        BufferVault(_asset, _feeProvider, _feeRecipient) {}

    function initialize_mock(address admin, string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __BaseVault_init(admin);
    }

    function reduceAssets(uint256 amount) external {
        require(amount <= totalAssets(), "Amount exceeds total assets");
        IERC20Metadata(asset()).safeTransfer(msg.sender, amount);
    }
}
