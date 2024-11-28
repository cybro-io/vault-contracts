// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {CYBROStaking} from "./CYBROStaking.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LockedCYBRO} from "./LockedCYBRO.sol";

contract LockedCYBROStaking is Ownable, CYBROStaking {
    constructor(address _owner, address _stakeToken, uint256 _lockTime, uint32 _percent)
        CYBROStaking(_owner, _stakeToken, _lockTime, _percent)
    {}

    function claim() public virtual override returns (uint256 reward) {
        UserState storage user = users[msg.sender];
        reward = getRewardOf(msg.sender);
        user.lastClaimTimestamp = block.timestamp;
        if (reward > 0) {
            address[] memory to = new address[](1);
            uint256[] memory amount = new uint256[](1);
            to[0] = msg.sender;
            amount[0] = reward;
            LockedCYBRO(address(stakeToken)).mint(to, amount);
            emit Claimed(msg.sender, reward);
        }
    }
}
