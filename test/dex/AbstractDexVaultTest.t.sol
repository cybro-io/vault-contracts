// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IDexVault} from "../../src/interfaces/IDexVault.sol";

abstract contract AbstractDexVaultTest is Test {
    IDexVault vault;
    uint256 amount;
    uint256 amountEth;
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
        forkId = vm.createSelectFork("blast", 8245770);
        user = address(100);
        user2 = address(101);
        amount = 3e21;
        amountEth = 5e18;
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeNewVault() internal virtual;

    function _deposit(address _user, bool inToken0, uint256 _amount) internal virtual returns (uint256 shares) {
        vm.startPrank(_user);
        if (inToken0) {
            token0.approve(address(vault), _amount);
        } else {
            token1.approve(address(vault), _amount);
        }
        uint160 sqrtPriceX96 = vault.getCurrentSqrtPrice();
        shares = vault.deposit(
            IDexVault.DepositInput(inToken0, _amount, _user, sqrtPriceX96 * 99 / 100, sqrtPriceX96 * 105 / 100)
        );
        vm.stopPrank();
    }

    function _redeem(address _owner, address _receiver, bool _inToken0, uint256 _shares)
        internal
        virtual
        returns (uint256 assets)
    {
        vm.startPrank(_receiver);
        assets = vault.redeem(_inToken0, _shares, _receiver, _owner, 0);
        vm.stopPrank();
    }

    function test_vault() public fork {
        _initializeNewVault();
        vm.prank(address(transferFromToken0));
        token0.transfer(user, amount);
        uint256 sharesUser = _deposit(user, true, amount);
        console.log("shares user", sharesUser);

        vm.prank(address(transferFromToken1));
        token1.transfer(user2, amountEth);
        uint256 sharesUser2 = _deposit(user2, false, amountEth);
        console.log("shares user2", sharesUser2);

        uint256 assets = _redeem(user, user, true, sharesUser);
        vm.assertApproxEqAbs(token0.balanceOf(user), amount, amount / 100);

        vm.expectRevert();
        _redeem(user2, user, true, sharesUser2);

        vm.prank(user2);
        IERC20Metadata(address(vault)).approve(user, sharesUser2);
        assets = _redeem(user2, user, false, sharesUser2);
        vm.startPrank(user);
        token1.transfer(user2, token1.balanceOf(user));
        vm.assertApproxEqAbs(token1.balanceOf(user2), amountEth, amountEth / 100);
        vm.stopPrank();
    }
}
