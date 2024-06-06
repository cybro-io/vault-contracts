// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {CErc20} from "../src/interfaces/compound/IcERC.sol";
import {CEth} from "../src/interfaces/compound/IcETH.sol";
import {CompoundVault, IERC20Metadata} from "../src/CompoundVaultErc20.sol";
import {CompoundVaultETH} from "../src/CompoundVaultEth.sol";

// 0x8C415331761063E5D6b1c8E700f996b13603Fc2E Orbit WBTC decimals 8
// 0x0872b71EFC37CB8DdE22B2118De3d800427fdba0 oEther V2 decimals 18
// 0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87 Orbit USDB decimals 18

contract CompoundVaultTest is Test {
    CErc20 usdbPool;
    CErc20 wbtcPool;
    CEth ethPool;
    CompoundVault vault;
    CompoundVaultETH vaultEth;
    IERC20Metadata usdb;
    IERC20Metadata wbtc;
    uint256 amount;
    uint256 wbtcAmount;
    uint256 ethAmount;
    uint256 forkId;
    address user;

    function setUp() public {
        forkId = vm.createSelectFork("https://rpc.blast.io/");
        usdbPool = CErc20(address(0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87));
        wbtcPool = CErc20(address(0x8C415331761063E5D6b1c8E700f996b13603Fc2E));
        ethPool = CEth(address(0x0872b71EFC37CB8DdE22B2118De3d800427fdba0));
        usdb = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        wbtc = IERC20Metadata(address(0xF7bc58b8D8f97ADC129cfC4c9f45Ce3C0E1D2692));
        amount = 1e19;
        wbtcAmount = 1 * 1e6;
        ethAmount = 1e18;
        user = address(100);
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function test_usdb() public fork {
        vm.prank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        usdb.transfer(user, amount);
        vault = new CompoundVault(usdb, usdbPool, "nameVault", "symbolVault");
        vm.startPrank(user);
        usdb.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(amount, user);

        console.log("shares", shares);
        vm.warp(block.timestamp + 100);
        console.log(vault.totalAssets(), usdbPool.balanceOf(address(vault)) * usdbPool.exchangeRateStored());
        console.log(usdbPool.balanceOfUnderlying(address(vault)));

        vault.redeem(shares, user, user);
        console.log(vault.totalAssets(), usdbPool.balanceOf(address(vault)) * usdbPool.exchangeRateStored());
        console.log(usdbPool.balanceOfUnderlying(address(vault)));
        vm.stopPrank();
    }

    function test_wbtc() public fork {
        vm.prank(address(0xecb1c17a51D782aC2757e2AB568d159854b9B4BD));
        wbtc.transfer(user, wbtcAmount);
        vault = new CompoundVault(wbtc, wbtcPool, "nameVault", "symbolVault");
        vm.startPrank(user);
        wbtc.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(wbtcAmount, user);

        console.log("shares", shares);
        vm.warp(block.timestamp + 100);
        vault.redeem(shares, user, user);
        vm.stopPrank();
    }

    function test_eth() public fork {
        deal(user, ethAmount);
        vaultEth = new CompoundVaultETH(ethPool, "nameVault", "symbolVault");
        vm.startPrank(user);
        vaultEth.approve(address(vaultEth), type(uint256).max);
        uint256 shares = vaultEth.depositEth{value: ethAmount}(user);

        console.log("shares", shares);
        vm.warp(block.timestamp + 100);
        vaultEth.redeem(shares, user, user);
        vm.stopPrank();
    }
}
