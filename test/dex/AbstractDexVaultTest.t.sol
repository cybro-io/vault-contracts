// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

abstract contract AbstractDexVaultTest is Test {
    uint256 amount;
    uint256 forkId;
    address user;
    address user2;

    address admin;
    uint256 adminPrivateKey;

    IERC20Metadata token0;
    IERC20Metadata token1;

    address transferFromToken0;
    address transferFromToken1;

    function setUp() public virtual {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast");
        user = address(100);
        user2 = address(101);
        amount = 1e19;
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _vault() internal view virtual returns (address);

    function _initializeNewVault() internal virtual;

    function _deposit(address _user, bool inToken0) internal virtual returns (uint256 shares);

    function _redeem(address _owner, address _receiver, bool _inToken0, uint256 _shares)
        internal
        virtual
        returns (uint256 assets);

    function test_vault() public fork {
        _initializeNewVault();
        vm.prank(address(transferFromToken0));
        token0.transfer(user, amount);
        uint256 sharesUser = _deposit(user, true);
        console.log("shares user", sharesUser);

        vm.prank(address(transferFromToken1));
        token1.transfer(user2, amount);
        uint256 sharesUser2 = _deposit(user2, false);
        console.log("shares user2", sharesUser2);

        uint256 assets = _redeem(user, user, true, sharesUser);
        vm.assertApproxEqAbs(token0.balanceOf(user), amount, 1e17);

        vm.expectRevert();
        _redeem(user2, user, true, sharesUser2);

        vm.prank(user2);
        IERC20Metadata(address(_vault())).approve(user, sharesUser2);
        assets = _redeem(user2, user, false, sharesUser2);
        vm.startPrank(user);
        token1.transfer(user2, token1.balanceOf(user));
        vm.assertApproxEqAbs(token1.balanceOf(user2), amount, 1e17);
        vm.stopPrank();
    }
}
