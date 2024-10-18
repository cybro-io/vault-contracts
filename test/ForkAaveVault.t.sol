// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {IAavePool} from "../src/interfaces/aave/IPool.sol";
import {AaveVault, IERC20Metadata, IFeeProvider} from "../src/AaveVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract AaveVaultTest is Test {
    IAavePool aavePool;
    AaveVault vault;
    IERC20Metadata token;
    uint256 amount;
    uint256 forkId;
    address user;
    address user2;

    address internal admin;
    uint256 internal adminPrivateKey;

    function setUp() public {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast", 8149175);
        aavePool = IAavePool(address(0xd2499b3c8611E36ca89A70Fda2A72C49eE19eAa8));
        amount = 1e20;
        user = address(100);
        user2 = address(101);
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _deposit() internal returns (uint256 shares) {
        vm.startPrank(admin);
        vault = AaveVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new AaveVault(token, aavePool, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(AaveVault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vm.stopPrank();
        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
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
        uint256 shares = _deposit();

        vm.prank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        token.transfer(address(aavePool), amount * 100);
        _redeem(shares);
        console.log(token.balanceOf(user));
        // vm.assertGt(assets, amount);
    }

    function test_weth_deposit() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token.transfer(user, amount);
        uint256 shares = _deposit();

        vm.prank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        token.transfer(address(aavePool), amount * 3);
        _redeem(shares);
        // vm.assertGt(assets, amount);
    }

    function test_otherTokens_deposit() public fork {
        token = IERC20Metadata(address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1));
        deal(address(token), user, amount);
        uint256 shares = _deposit();

        deal(address(token), address(aavePool), token.balanceOf(address(aavePool)) + amount * 3);
        _redeem(shares);
        // vm.assertGt(assets, amount);
    }
}
