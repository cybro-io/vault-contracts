// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {CErc20} from "../src/interfaces/compound/IcERC.sol";
import {CEth} from "../src/interfaces/compound/IcETH.sol";
import {CompoundVault, IERC20Metadata} from "../src/vaults/CompoundVaultErc20.sol";
import {CompoundVaultETH} from "../src/vaults/CompoundVaultEth.sol";
import {
    TransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FeeProvider, IFeeProvider} from "../src/FeeProvider.sol";

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
    IERC20Metadata weth;
    uint256 amount;
    uint256 wbtcAmount;
    uint256 ethAmount;
    uint256 forkId;
    address user;
    address user2;
    address internal admin;
    uint256 internal adminPrivateKey;
    uint32 feePrecision;
    IFeeProvider feeProvider;
    address feeRecipient;
    uint32 depositFee;
    uint32 withdrawalFee;
    uint32 performanceFee;

    function setUp() public {
        adminPrivateKey = 0xba132ce;
        admin = vm.addr(adminPrivateKey);
        forkId = vm.createSelectFork("blast", 8149175);
        usdbPool = CErc20(address(0x9aECEdCD6A82d26F2f86D331B17a1C1676442A87));
        wbtcPool = CErc20(address(0x8C415331761063E5D6b1c8E700f996b13603Fc2E));
        ethPool = CEth(address(0x0872b71EFC37CB8DdE22B2118De3d800427fdba0));
        usdb = IERC20Metadata(address(0x4300000000000000000000000000000000000003));
        wbtc = IERC20Metadata(address(0xF7bc58b8D8f97ADC129cfC4c9f45Ce3C0E1D2692));
        amount = 1e19;
        wbtcAmount = 1 * 1e6;
        ethAmount = 1e18;
        user = address(100);
        user2 = address(101);
        feeRecipient = address(102);
        depositFee = 0;
        withdrawalFee = 0;
        performanceFee = 100;
        feePrecision = 1e5;
        vm.startPrank(admin);
        address vaultAddress = vm.computeCreateAddress(admin, vm.getNonce(admin) + 3);
        feeProvider = FeeProvider(
            address(
                new TransparentUpgradeableProxy(
                    address(new FeeProvider(feePrecision)),
                    admin,
                    abi.encodeCall(FeeProvider.initialize, (admin, depositFee, withdrawalFee, performanceFee))
                )
            )
        );
        address[] memory associatedContracts = new address[](1);
        associatedContracts[0] = vaultAddress;
        bool[] memory isAssociated = new bool[](1);
        isAssociated[0] = true;
        feeProvider.setAssociatedContracts(associatedContracts, isAssociated);
        vm.stopPrank();
    }

    modifier fork() {
        vm.selectFork(forkId);
        _;
    }

    function test_usdb() public fork {
        vm.startPrank(address(0x3Ba925fdeAe6B46d0BB4d424D829982Cb2F7309e));
        usdb.transfer(user, amount);
        usdb.transfer(admin, amount);
        vm.stopPrank();
        vm.startPrank(admin);
        usdb.approve(vm.computeCreateAddress(admin, vm.getNonce(admin) + 1), amount);
        vault = CompoundVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new CompoundVault(usdb, usdbPool, IFeeProvider(feeProvider), feeRecipient)),
                    admin,
                    abi.encodeCall(CompoundVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        vm.stopPrank();
        vm.startPrank(user);
        usdb.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(amount, user, 0);

        console.log("shares", shares);
        vm.stopPrank();
        
        vm.startPrank(admin);
        feeProvider.setFees(depositFee * 2, withdrawalFee * 2, performanceFee * 2);
        vm.assertEq(vault.getDepositFee(user), depositFee);
        vm.assertEq(vault.getWithdrawalFee(user), withdrawalFee);
        vm.assertEq(vault.getPerformanceFee(user), performanceFee);
        vm.assertEq(vault.getDepositFee(user2), depositFee * 2);
        vm.assertEq(vault.getWithdrawalFee(user2), withdrawalFee * 2);
        vm.assertEq(vault.getPerformanceFee(user2), performanceFee * 2);
        feeProvider.setFees(depositFee, withdrawalFee, performanceFee);
        vm.stopPrank();

        vm.startPrank(user);
        vm.warp(block.timestamp + 100);
        console.log(vault.totalAssets(), usdbPool.balanceOf(address(vault)) * usdbPool.exchangeRateStored());
        console.log(usdbPool.balanceOfUnderlying(address(vault)));
        vault.approve(user2, shares);

        vm.stopPrank();
        vm.startPrank(user2);
        vault.redeem(shares, user, user, 0);
        console.log(vault.totalAssets(), usdbPool.balanceOf(address(vault)) * usdbPool.exchangeRateStored());
        console.log(usdbPool.balanceOfUnderlying(address(vault)));
        vm.stopPrank();
    }

    function test_wbtc() public fork {
        vm.startPrank(address(0xecb1c17a51D782aC2757e2AB568d159854b9B4BD));
        wbtc.transfer(user, wbtcAmount);
        wbtc.transfer(admin, 10 ** wbtc.decimals());
        vm.stopPrank();
        vm.startPrank(admin);
        address vaultAddress = vm.computeCreateAddress(admin, vm.getNonce(admin) + 1);
        wbtc.approve(vaultAddress, 10 ** wbtc.decimals());
        vault = CompoundVault(
            address(
                new TransparentUpgradeableProxy(
                    address(new CompoundVault(wbtc, wbtcPool, IFeeProvider(address(0)), address(0))),
                    admin,
                    abi.encodeCall(CompoundVault.initialize, (admin, "nameVault", "symbolVault", admin))
                )
            )
        );
        vm.stopPrank();
        vm.startPrank(user);
        wbtc.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(wbtcAmount, user, 0);

        console.log("shares", shares);
        vm.warp(block.timestamp + 100);
        vault.redeem(shares, user, user, 0);
        vm.stopPrank();
    }

    function test_eth() public fork {
        weth = IERC20Metadata(address(0x4300000000000000000000000000000000000004));
        vm.startPrank(address(0x44f33bC796f7d3df55040cd3C631628B560715C2));
        weth.transfer(user, ethAmount);
        weth.transfer(admin, 10 ** weth.decimals() * 2);
        vm.stopPrank();
        vm.startPrank(admin);
        address vaultAddress = vm.computeCreateAddress(admin, vm.getNonce(admin) + 1);
        weth.approve(vaultAddress, 10 ** weth.decimals() * 2);
        vaultEth = CompoundVaultETH(
            payable(
                address(
                    new TransparentUpgradeableProxy(
                        address(new CompoundVaultETH(weth, ethPool, IFeeProvider(address(0)), address(0))),
                        admin,
                        abi.encodeCall(CompoundVaultETH.initialize, (admin, "nameVault", "symbolVault", admin))
                    )
                )
            )
        );
        vm.stopPrank();
        vm.startPrank(user);
        weth.approve(address(vaultEth), type(uint256).max);
        uint256 shares = vaultEth.deposit(ethAmount, user, 0);

        console.log("shares", shares);
        vm.warp(block.timestamp + 100);
        uint256 underlyingAssets = vaultEth.redeem(shares, user, user, 0);
        vm.assertApproxEqAbs(weth.balanceOf(user), underlyingAssets, 1);
        vm.stopPrank();
    }
}
