// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {InitVault, IERC20Metadata} from "../src/InitVault.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IInitCore} from "../src/interfaces/init/IInitCore.sol";
import {IERC20RebasingWrapper} from "../src/interfaces/init/IERC20RebasingWrapper.sol";
import {IInitLendingPool} from "../src/interfaces/init/IInitLendingPool.sol";

contract InitVaultTest is Test {
    IERC20Metadata usdbPool;
    IERC20Metadata wethPool;
    IERC20Metadata blastPool;
    InitVault usdbVault;
    InitVault wethVault;
    InitVault blastVault;
    IInitCore core;
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
        forkId = vm.createSelectFork("blast", 9330000);
        usdbPool = IERC20Metadata(address(0xc5EaC92633aF47c0023Afa0116500ab86FAB430F));
        wethPool = IERC20Metadata(address(0xD20989EB39348994AA99F686bb4554090d0C09F3));
        blastPool = IERC20Metadata(address(0xdafB6929442303e904A2f673A0E7EB8753Bab571));
        core = IInitCore(address(0xa7d36f2106b5a5D528a7e2e7a3f436d703113A10));
        amount = 1e20;
        user = address(100);
        user2 = address(101);
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function _initializeNewVault(IERC20Metadata _token, IERC20Metadata _pool) internal returns (InitVault vault) {
        vm.startPrank(admin);
        vault = InitVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new InitVault(_token, core, _pool)),
                    admin,
                    abi.encodeCall(InitVault.initialize, (admin, "nameVault", "symbolVault"))
                )
            )
        );
        vm.stopPrank();
    }

    function _deposit(InitVault vault) internal returns (uint256 shares) {
        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _redeem(uint256 shares, InitVault vault) internal returns (uint256 assets) {
        vm.startPrank(user);
        assets = vault.redeem(shares, user, user);
        vm.stopPrank();
    }

    function test_usdb() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        usdbVault = _initializeNewVault(token, usdbPool);
        vm.prank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        token.transfer(user, amount);

        // tests pause
        vm.prank(admin);
        usdbVault.pause();
        vm.startPrank(user);
        token.approve(address(usdbVault), amount);
        vm.expectRevert();
        usdbVault.deposit(amount, user);
        vm.stopPrank();
        vm.prank(admin);
        usdbVault.unpause();

        uint256 shares = _deposit(usdbVault);
        console.log("shares", shares);
        // console.log("decimals", IERC20Metadata(IInitLendingPool(address(usdbPool)).underlyingToken()).decimals());
        console.log("balance", usdbPool.balanceOf(address(usdbVault)));
        // decimals of pool's lp = usdb.decimals + 16 = wusdb.decimlas + 8
        // wusdb.decimals = usdb.decimals + 8

        vm.warp(block.timestamp + 100);
        IInitLendingPool(address(usdbPool)).accrueInterest();
        uint256 assets = _redeem(shares, usdbVault);
        console.log(token.balanceOf(user));
        vm.assertGt(assets, amount);
    }

    function test_blast() public fork {
        token = IERC20Metadata(address(0xb1a5700fA2358173Fe465e6eA4Ff52E36e88E2ad));
        blastVault = _initializeNewVault(token, blastPool);
        vm.prank(address(0xCB4A7EeE965CB1A0f28931a125Ef360d058892DE));
        token.transfer(user, amount);

        uint256 shares = _deposit(blastVault);
        console.log("shares", shares);
        console.log("underlying", address(blastVault.underlying()));

        vm.warp(block.timestamp + 100);
        IInitLendingPool(address(blastPool)).accrueInterest();
        uint256 assets = _redeem(shares, blastVault);
        console.log(token.balanceOf(user));
        vm.assertGt(assets, amount);
    }

    function test_weth() public fork {
        token = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        wethVault = _initializeNewVault(token, wethPool);
        vm.prank(address(0x66714DB8F3397c767d0A602458B5b4E3C0FE7dd1));
        token.transfer(user, amount);
        uint256 shares = _deposit(wethVault);
        console.log("shares", shares);
        console.log("underlying", address(wethVault.underlying()));

        vm.warp(block.timestamp + 100);
        IInitLendingPool(address(wethPool)).accrueInterest();
        uint256 assets = _redeem(shares, wethVault);
        console.log(token.balanceOf(user));
        vm.assertGt(assets, amount);
    }
}
