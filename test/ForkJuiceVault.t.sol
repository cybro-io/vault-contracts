// // SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {JuiceVault, IERC20Metadata, IFeeProvider} from "../src/JuiceVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IJuicePool} from "../src/interfaces/juice/IJuicePool.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// 0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a Juice usdb lending pool
// 0x44f33bC796f7d3df55040cd3C631628B560715C2 Juice weth lending pool

contract JuiceVaultTest is Test {
    IJuicePool usdbPool;
    IJuicePool wethPool;
    JuiceVault vault;
    IERC20Metadata token;
    uint256 amount;
    uint256 forkId;
    address user;
    address internal admin;
    uint256 internal adminPrivateKey;

    function setUp() public {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast", 8149175);
        usdbPool = IJuicePool(address(0x4A1d9220e11a47d8Ab22Ccd82DA616740CF0920a));
        wethPool = IJuicePool(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        amount = 1e20;
        user = address(100);
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _redeem(uint256 shares) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = vault.redeem(shares, user, user);
        vm.stopPrank();
    }

    function test_usdb() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        vm.prank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        token.transfer(user, amount);
        vm.startPrank(admin);
        vault = JuiceVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new JuiceVault(token, usdbPool, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(JuiceVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        vm.stopPrank();
        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user);
        vm.stopPrank();

        vm.prank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        token.transfer(address(usdbPool), amount * 100);
        _redeem(shares);
        console.log(token.balanceOf(user));
        // vm.assertGt(assets, amount);
    }

    function test_weth_deposit() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token.transfer(user, amount);
        vm.startPrank(admin);
        vault = JuiceVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new JuiceVault(token, wethPool, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(JuiceVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        vm.stopPrank();
        vm.startPrank(user);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, user);
        vm.stopPrank();

        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token.transfer(address(wethPool), amount * 3);
        _redeem(shares);
        console.log(token.balanceOf(user));
        // vm.assertGt(assets, amount);
    }
}
