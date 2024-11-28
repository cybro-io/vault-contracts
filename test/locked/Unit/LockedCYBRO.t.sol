// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseLockedCYBRO} from "../BaseLockedCYBRO.t.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract LockedCYBROTest is BaseLockedCYBRO {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    function test_settersConstants() public {
        vm.assertEq(lockedCYBRO.name(), "CYBRO Locked Token");
        vm.assertEq(lockedCYBRO.symbol(), "LCYBRO");

        vm.startPrank(admin);
        lockedCYBRO.setTgePercent(20);
        vm.assertEq(lockedCYBRO.tgePercent(), 20);

        vm.warp(100);
        vm.expectRevert("CYBRO: invalid tge timestamp");
        lockedCYBRO.setTgeTimestamp(block.timestamp - 10);
        vm.expectRevert("CYBRO: invalid vesting start");
        lockedCYBRO.setVestingStart(block.timestamp - 20);

        lockedCYBRO.setTgeTimestamp(1100);
        vm.assertEq(lockedCYBRO.tgeTimestamp(), 1100);
        lockedCYBRO.setVestingStart(2200);
        vm.assertEq(lockedCYBRO.vestingStart(), 2200);
        lockedCYBRO.setVestingDuration(15000);
        vm.assertEq(lockedCYBRO.vestingDuration(), 15000);

        vm.assertEq(lockedCYBRO.transferWhitelist(user2), false);
        lockedCYBRO.addWhitelistedAddress(user2);
        vm.assertEq(lockedCYBRO.transferWhitelist(user2), true);
        vm.stopPrank();
    }

    function test_RevertTransfers() public {
        vm.startPrank(admin);
        lockedCYBRO.setMintableByUsers(false);
        address[] memory to = new address[](1);
        uint256[] memory amount = new uint256[](1);
        to[0] = user;
        amount[0] = 100 * 1e18;
        lockedCYBRO.mint(to, amount);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("CYBRO: not whitelisted");
        lockedCYBRO.transfer(user2, 1e18);
        vm.stopPrank();
    }

    function test_mintByUser() public {
        uint256 amount = 100 * 1e18;
        bytes32 ethSignedMessageHash =
            keccak256(abi.encodePacked(user, amount, address(lockedCYBRO), block.chainid)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        lockedCYBRO.mintByUser(user, amount, signature);
        assertEq(lockedCYBRO.balanceOf(user), amount);
        assertEq(lockedCYBRO.allocations(user), amount);

        lockedCYBRO.mintByUser(user, amount, signature);
        assertEq(lockedCYBRO.balanceOf(user), amount);
        assertEq(lockedCYBRO.allocations(user), amount);

        uint256 unauthorizedPrivateKey = 0xbad;
        (v, r, s) = vm.sign(unauthorizedPrivateKey, ethSignedMessageHash);
        bytes memory unauthorizedSignature = abi.encodePacked(r, s, v);

        vm.expectRevert("CYBRO: Invalid signature");
        lockedCYBRO.mintByUser(user, amount, unauthorizedSignature);

        uint256 wrongAmount = 200 * 1e18;
        bytes32 wrongEthSignedMessageHash =
            keccak256(abi.encodePacked(user, wrongAmount, address(lockedCYBRO), block.chainid)).toEthSignedMessageHash();
        (v, r, s) = vm.sign(adminPrivateKey, wrongEthSignedMessageHash);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        vm.expectRevert("CYBRO: Invalid signature");
        lockedCYBRO.mintByUser(user, amount, wrongSignature);
    }

    function test_claim() public {
        vm.startPrank(admin);
        lockedCYBRO.setMintableByUsers(false);
        address[] memory to = new address[](1);
        uint256[] memory amount = new uint256[](1);
        to[0] = user;
        amount[0] = 100 * 1e18;
        uint256 tgeAmount = amount[0] * lockedCYBRO.tgePercent() / 100;
        lockedCYBRO.mint(to, amount);
        cbr.mint(address(lockedCYBRO), amount[0]);
        vm.stopPrank();

        vm.assertEq(lockedCYBRO.getClaimableAmount(user), 0);
        vm.warp(lockedCYBRO.tgeTimestamp());
        vm.assertEq(lockedCYBRO.getUnlockedAmount(user), tgeAmount);
        vm.prank(user);
        lockedCYBRO.claim();
        vm.assertEq(cbr.balanceOf(user), tgeAmount);
        vm.warp(lockedCYBRO.vestingStart() + lockedCYBRO.vestingDuration());
        vm.prank(user);
        lockedCYBRO.claim();
        vm.assertEq(cbr.balanceOf(user), amount[0]);
    }
}
